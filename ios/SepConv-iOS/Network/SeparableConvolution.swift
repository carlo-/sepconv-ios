//
//  SeparableConvolution.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-11.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import CoreML
import MetalKit


// MARK: - Separable Convolution

class SeparableConvolution {
    
    private let threadgroupSize = MTLSize(width: 1, height: 1, depth: 1)
    
    private let filterLength: Int
    private let imageDepth: Int
    private let inputShape: [Int]
    private let outputShape: [Int]
    private let verticalShape: [Int]
    private let horizontalShape: [Int]
    
    private var inputHeight: Int {
        return inputShape[3]
    }
    
    private var inputWidth: Int {
        return inputShape[4]
    }
    
    private var outputHeight: Int {
        return outputShape[3]
    }
    
    private var outputWidth: Int {
        return outputShape[4]
    }
    
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private var device: MTLDevice?
    
    private var shaderInfo = SepConvShaderInfo.zeros
    
    private var iBuffer: MTLBuffer?
    private var oBuffer: MTLBuffer?
    private var vBuffer: MTLBuffer?
    private var hBuffer: MTLBuffer?
    private var infoBuffer: MTLBuffer?
    
    init(filterLength: Int, networkInputSide: Int, imageDepth: Int) {
        
        let imageHeight = networkInputSide
        let imageWidth = networkInputSide
        
        self.filterLength = filterLength
        self.inputShape = [1, 1, imageDepth, imageHeight + filterLength - 1, imageWidth + filterLength - 1]
        self.outputShape = [1, 1, imageDepth, imageHeight, imageWidth]
        self.verticalShape = [1, 1, filterLength, imageHeight, imageWidth]
        self.horizontalShape = [1, 1, filterLength, imageHeight, imageWidth]
        self.imageDepth = imageDepth
    }
    
    func prepareForMetal() throws {
        
        device = MTLCreateSystemDefaultDevice()
        let library = device?.makeDefaultLibrary()
        guard let sepConvFunction = library?.makeFunction(name: "separable_convolution") else {
            fatalError()
        }
        
        pipelineState = try device?.makeComputePipelineState(function: sepConvFunction)
        commandQueue = device?.makeCommandQueue()
        
        try prepareBuffers()
    }
    
    private func prepareBuffers() throws {
        
        let memStride = MemoryLayout<Float32>.stride
        let iBufferSize = inputShape.prod() * memStride
        guard let iBuffer = device?.makeBuffer(length: iBufferSize, options: .storageModeShared) else {
            throw SepConvError.cannotAllocateVideoMemory
        }
        
        let oBufferSize = outputShape.prod() * memStride
        guard let oBuffer = device?.makeBuffer(length: oBufferSize, options: .storageModeShared) else {
            throw SepConvError.cannotAllocateVideoMemory
        }
        
        let vBufferSize = verticalShape.prod() * memStride
        guard let vBuffer = device?.makeBuffer(length: vBufferSize, options: .storageModeShared) else {
            throw SepConvError.cannotAllocateVideoMemory
        }
        
        let hBufferSize = horizontalShape.prod() * memStride
        guard let hBuffer = device?.makeBuffer(length: hBufferSize, options: .storageModeShared) else {
            throw SepConvError.cannotAllocateVideoMemory
        }
        
        let infoBufferSize = MemoryLayout.stride(ofValue: shaderInfo)
        guard let infoBuffer = device?.makeBuffer(length: infoBufferSize, options: .storageModeShared) else {
            throw SepConvError.cannotAllocateVideoMemory
        }
        
        self.iBuffer = iBuffer
        self.oBuffer = oBuffer
        self.vBuffer = vBuffer
        self.hBuffer = hBuffer
        self.infoBuffer = infoBuffer
    }
    
    func makeOutputArray() throws -> MLMultiArray {
        let shape = [1, 1, self.imageDepth, outputHeight, outputWidth] as [NSNumber]
        return try MLMultiArray(shape: shape, dataType: .float32)
    }
    
    func forward(input: MLMultiArray, vertical: MLMultiArray, horizontal: MLMultiArray, output: MLMultiArray) throws {
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipelineState = pipelineState,
              let iBuffer = iBuffer, let oBuffer = oBuffer, let vBuffer = vBuffer, let hBuffer = hBuffer,
              let infoBuffer = infoBuffer else {
            throw SepConvError.sepConvNotConfigured
        }
        
        encoder.setComputePipelineState(pipelineState)
        
        shaderInfo = SepConvShaderInfo(
            inputSize: input.int4shape, inputStride: input.int4stride,
            verticalSize: vertical.int4shape, verticalStride: vertical.int4stride,
            horizontalSize: horizontal.int4shape, horizontalStride: horizontal.int4stride,
            outputSize: output.int4shape, outputStride: int4(1, 1, 1, 1),
            filterSize: Int32(filterLength)
        )
        
        iBuffer.update(from: input)
        vBuffer.update(from: vertical)
        hBuffer.update(from: horizontal)
        infoBuffer.contents().copyMemory(from: &shaderInfo, byteCount: infoBuffer.length)
        
        encoder.setBuffer(iBuffer, offset: 0, index: 0)
        encoder.setBuffer(oBuffer, offset: 0, index: 1)
        encoder.setBuffer(vBuffer, offset: 0, index: 2)
        encoder.setBuffer(hBuffer, offset: 0, index: 3)
        encoder.setBuffer(infoBuffer, offset: 0, index: 4)
        
        var threadgroupCount = MTLSize()
        threadgroupCount.width  = (inputWidth + threadgroupSize.width -  1) / threadgroupSize.width
        threadgroupCount.height = (inputHeight + threadgroupSize.height - 1) / threadgroupSize.height
        threadgroupCount.depth = self.imageDepth
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        oBuffer.toMLMultiArray(output)
    }
    
    func forward(input: MLMultiArray, vertical: MLMultiArray, horizontal: MLMultiArray) throws -> MLMultiArray {
        let output = try makeOutputArray()
        try forward(input: input, vertical: vertical, horizontal: horizontal, output: output)
        return output
    }
}


// MARK: - Shader Data Structs.

private struct SepConvShaderInfo {
    let inputSize: int4
    let inputStride: int4
    
    let verticalSize: int4
    let verticalStride: int4
    
    let horizontalSize: int4
    let horizontalStride: int4
    
    let outputSize: int4
    let outputStride: int4
    
    let filterSize: Int32
    
    static var zeros: SepConvShaderInfo {
        return SepConvShaderInfo(
            inputSize: .zero, inputStride: .zero,
            verticalSize: .zero, verticalStride: .zero,
            horizontalSize: .zero, horizontalStride: .zero,
            outputSize: .zero, outputStride: .zero,
            filterSize: 0
        )
    }
}


// MARK: - Utilities

extension Array where Element == Int {
    func prod() -> Int {
        return reduce(1, *)
    }
}
