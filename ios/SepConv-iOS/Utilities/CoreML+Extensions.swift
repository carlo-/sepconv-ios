//
//  CoreML+Extensions.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-14.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import UIKit
import CoreML
import MetalKit
import Accelerate


extension MLMultiArray {
    
    var byteCount: Int {
        switch dataType {
        case .double:
            return count * MemoryLayout<Float64>.stride
        case .float32:
            return count * MemoryLayout<Float32>.stride
        case .int32:
            return count * MemoryLayout<Int32>.stride
        @unknown default:
            fatalError()
        }
    }
    
    var int4shape: int4 {
        return int4(shape[1].int32Value, shape[2].int32Value, shape[3].int32Value, shape[4].int32Value)
    }
    
    var int4stride: int4 {
        return int4(strides[1].int32Value, strides[2].int32Value, strides[3].int32Value, strides[4].int32Value)
    }
    
    static func random(_ shape: [UInt]) -> MLMultiArray {
        let res = try! MLMultiArray(shape: shape as [NSNumber], dataType: .float32)
        let ptr = res.dataPointer.assumingMemoryBound(to: Float32.self)
        for i in 0..<res.count {
            ptr.advanced(by: i).initialize(to: Float32(arc4random()))
        }
        return res
    }
    
    static func arange(_ shape: [UInt]) -> MLMultiArray {
        let res = try! MLMultiArray(shape: shape as [NSNumber], dataType: .float32)
        let ptr = res.dataPointer.assumingMemoryBound(to: Float32.self)
        for i in 0..<res.count {
            ptr.advanced(by: i).initialize(to: Float32(i))
        }
        return res
    }
    
    func prettyPrint() {
        print(self)
        if shape.count != 5 || shape[0].intValue > 1 || shape[1].intValue > 1 {
            print("Cannot pretty print array of this shape.")
        }
        let planes = shape[2].intValue
        let height = shape[3].intValue
        let width = shape[4].intValue
        let planeSize = height * width
        let ptr = dataPointer.assumingMemoryBound(to: Float32.self)
        for p in 0..<planes {
            if planes > 1 {
                if p > 0 { print("") }
                print("Plane \(p):")
            }
            let planePtr = ptr.advanced(by: p * planeSize)
            for i in 0..<height {
                let bufferPtr = UnsafeBufferPointer(start: planePtr.advanced(by: width * i), count: width)
                let row = Array(bufferPtr)
                if i == 0 {
                    print("[", terminator: "")
                } else {
                    print(" ", terminator: "")
                }
                print(row, terminator: "")
                if i == height - 1 {
                    print("]", terminator: "")
                }
                print("")
            }
        }
    }
    
    func toArray() -> [Float32] {
        let pointer = dataPointer.assumingMemoryBound(to: Float32.self)
        let bufferPointer = UnsafeBufferPointer(start: pointer, count: count)
        return Array(bufferPointer)
    }
    
    static func fromArray(_ array: [Float32], shape: [NSNumber]) -> MLMultiArray {
        let res = try! MLMultiArray(shape: shape, dataType: .float32)
        let desPointer = res.dataPointer.assumingMemoryBound(to: Float32.self)
        let srcPointer = UnsafePointer(array)
        cblas_scopy(Int32(array.count), srcPointer, 1, desPointer, 1)
        return res
    }
    
    static func fromImage(_ image: UIImage) -> MLMultiArray? {
        if let cgImage = image.cgImage {
            return fromImage(cgImage)
        } else {
            return nil
        }
    }
    
    private static func fromBufferUInt8(_ buffer: UnsafePointer<UInt8>, height: Int, width: Int,
                                        littleEndian: Bool, alphaFirst: Bool) -> MLMultiArray? {
        
        let shape = [1, 1, 3, height, width] as [NSNumber]
        guard let res = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }
        let arrPointer = res.dataPointer.assumingMemoryBound(to: Float32.self)
        
        let planeSize = height * width
        let count = vDSP_Length(planeSize * 4)
        
        var tmpBuffer = [Float32](repeating: 0, count: Int(count))
        let tmpBufferPtr = UnsafeMutablePointer(&tmpBuffer)
        
        let rgbOffsets: [Int]
        if littleEndian {
            if alphaFirst {
                // bgra
                rgbOffsets = [2, 1, 0]
            } else {
                // abgr
                rgbOffsets = [3, 2, 1]
            }
        } else if alphaFirst {
            // argb
            rgbOffsets = [1, 2, 3]
        } else {
            // rgba
            rgbOffsets = [0, 1, 2]
        }
        
        // Convert buffer to Float32 values
        vDSP_vfltu8(buffer, 1, tmpBufferPtr, 1, count)
        
        // Divide values by 255 to map them to [0, 1]
        var div: Float32 = 255
        vDSP_vsdiv(tmpBuffer, 1, &div, tmpBufferPtr, 1, count)
        
        // Copy red channel
        cblas_scopy(Int32(planeSize), tmpBufferPtr.advanced(by: rgbOffsets[0]), 4, arrPointer.advanced(by: 0 * planeSize), 1)
        
        // Copy green channel
        cblas_scopy(Int32(planeSize), tmpBufferPtr.advanced(by: rgbOffsets[1]), 4, arrPointer.advanced(by: 1 * planeSize), 1)
        
        // Copy blue channel
        cblas_scopy(Int32(planeSize), tmpBufferPtr.advanced(by: rgbOffsets[2]), 4, arrPointer.advanced(by: 2 * planeSize), 1)
        
        return res
    }
    
    static func fromBufferRGBA(_ buffer: UnsafePointer<UInt8>, height: Int, width: Int) -> MLMultiArray? {
        return fromBufferUInt8(buffer, height: height, width: width, littleEndian: false, alphaFirst: false)
    }
    
    static func fromBufferARGB(_ buffer: UnsafePointer<UInt8>, height: Int, width: Int) -> MLMultiArray? {
        return fromBufferUInt8(buffer, height: height, width: width, littleEndian: false, alphaFirst: true)
    }
    
    static func fromImage(_ image: CGImage) -> MLMultiArray? {
        
        if let providerData = image.dataProvider?.data,
            let data = CFDataGetBytePtr(providerData) {
            
            let alphaInfo = image.alphaInfo
            let alphaFirst = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst
            let littleEndian = image.bitmapInfo.contains(.byteOrder32Little)
            
            if alphaInfo == .alphaOnly || alphaInfo == .none {
                return nil
            }
            
            return fromBufferUInt8(data, height: image.height, width: image.width, littleEndian: littleEndian, alphaFirst: alphaFirst)
            
        } else {
            return nil
        }
    }
    
    func toArrayRGBA() -> [UInt8] {
        let height = shape[3].intValue
        let width = shape[4].intValue
        let planeSize = height * width
        
        var res = [UInt8](repeating: 0, count: 4 * planeSize)
        let arrPointer = dataPointer.assumingMemoryBound(to: Float32.self)
        
        var tmpBuffer = [Float32](repeating: 1, count: res.count)
        let tmpBufferPtr = UnsafeMutablePointer(&tmpBuffer)
        
        // Copy red channel
        cblas_scopy(Int32(planeSize), arrPointer.advanced(by: 0 * planeSize), 1, tmpBufferPtr.advanced(by: 0), 4)
        
        // Copy green channel
        cblas_scopy(Int32(planeSize), arrPointer.advanced(by: 1 * planeSize), 1, tmpBufferPtr.advanced(by: 1), 4)
        
        // Copy blue channel
        cblas_scopy(Int32(planeSize), arrPointer.advanced(by: 2 * planeSize), 1, tmpBufferPtr.advanced(by: 2), 4)
        
        // Multiply values by 255 to map them to [0, 255]
        var factor: Float32 = 255
        vDSP_vsmul(tmpBuffer, 1, &factor, tmpBufferPtr, 1, vDSP_Length(res.count))
        
        // Convert array to UInt8 values
        vDSP_vfixu8(tmpBuffer, 1, &res, 1, vDSP_Length(res.count))
        
        return res
    }
    
    func toCGImage() -> CGImage? {
        
        let height = shape[3].intValue
        let width = shape[4].intValue
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let pixelSize = MemoryLayout<UInt8>.stride
        
        var data = toArrayRGBA()
        guard let providerRef = CGDataProvider(data: NSData(bytes: &data, length: data.count * pixelSize)) else {
            return nil
        }
        
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: width * pixelSize * 4,
            space: rgbColorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        
        return cgImage
    }
    
    func toUIImage() -> UIImage? {
        if let cgImage = toCGImage() {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    
    func trim2D(left: Int, right: Int, top: Int, bottom: Int) -> MLMultiArray {
        
        assert(left >= 0 && right >= 0 && top >= 0 && bottom >= 0)
        assert(shape.count == 5)
        assert(shape[0].intValue == 1 && shape[1].intValue == 1)
        assert(dataType == .float32)
        
        let height = shape[3].intValue
        let width = shape[4].intValue
        let planes = shape[2].intValue
        let planeSize = height * width
        let arrPointer = dataPointer.assumingMemoryBound(to: Float32.self)
        
        let outHeight = height - top - bottom
        let outWidth = width - left - right
        assert(outHeight > 0 && outWidth > 0)
        let outPlaneSize = outHeight * outWidth
        let outArr = try! MLMultiArray(shape: [1, 1, planes, outHeight, outWidth] as [NSNumber], dataType: .float32)
        let outArrPointer = outArr.dataPointer.assumingMemoryBound(to: Float32.self)
        
        for planeIdx in 0..<planes {
            
            let planePointer = arrPointer.advanced(by: planeSize * planeIdx)
            let outPlanePointer = outArrPointer.advanced(by: outPlaneSize * planeIdx)
            
            for i in 0..<outHeight {
                let srcPointer = planePointer.advanced(by: width * (top + i) + left)
                let desPointer = outPlanePointer.advanced(by: i * outWidth)
                cblas_scopy(Int32(outWidth), srcPointer, 1, desPointer, 1)
            }
        }
        
        return outArr
    }
    
    func replicationPad2D(left: Int, right: Int, top: Int, bottom: Int) -> MLMultiArray {
        
        assert(left >= 0 && right >= 0 && top >= 0 && bottom >= 0)
        assert(shape.count == 5)
        assert(shape[0].intValue == 1 && shape[1].intValue == 1)
        assert(dataType == .float32)
        
        let height = shape[3].intValue
        let width = shape[4].intValue
        let planes = shape[2].intValue
        let planeSize = height * width
        let arrPointer = dataPointer.assumingMemoryBound(to: Float32.self)
        
        let outHeight = height + top + bottom
        let outWidth = width + left + right
        let outPlaneSize = outHeight * outWidth
        let outArr = try! MLMultiArray(shape: [1, 1, planes, outHeight, outWidth] as [NSNumber], dataType: .float32)
        let outArrPointer = outArr.dataPointer.assumingMemoryBound(to: Float32.self)
        
        for planeIdx in 0..<planes {
            
            let planePointer = arrPointer.advanced(by: planeSize * planeIdx)
            let outPlanePointer = outArrPointer.advanced(by: outPlaneSize * planeIdx)
            
            // Center
            for i in 0..<height {
                let stride = outWidth
                let offset = outWidth * top + left
                let srcPointer = planePointer.advanced(by: i * width)
                let desPointer = outPlanePointer.advanced(by: offset + i * stride)
                cblas_scopy(Int32(width), srcPointer, 1, desPointer, 1)
            }
            
            // Top
            for i in 0..<top {
                let stride = outWidth
                let offset = left
                let srcPointer = planePointer
                let desPointer = outPlanePointer.advanced(by: offset + i * stride)
                cblas_scopy(Int32(width), srcPointer, 1, desPointer, 1)
            }
            
            // Bottom
            for i in 0..<bottom {
                let stride = outWidth
                let offset = outWidth * (top + height) + left
                let srcPointer = planePointer.advanced(by: width * (height - 1))
                let desPointer = outPlanePointer.advanced(by: offset + i * stride)
                cblas_scopy(Int32(width), srcPointer, 1, desPointer, 1)
            }
        }
        
        if left > 0 || right > 0 {
            
            var tmpArr = [Float](repeating: 0, count: outPlaneSize)
            let tmpArrPointer = UnsafeMutablePointer(&tmpArr)
            
            for planeIdx in 0..<planes {
                
                let outPlanePointer = outArrPointer.advanced(by: outPlaneSize * planeIdx)
                
                // Transpose
                vDSP_mtrans(outPlanePointer, 1, tmpArrPointer, 1, vDSP_Length(outWidth), vDSP_Length(outHeight))
                
                // Transposed top (original left)
                for i in 0..<left {
                    let srcPointer = tmpArrPointer.advanced(by: left * outHeight)
                    let desPointer = tmpArrPointer.advanced(by: i * outHeight)
                    cblas_scopy(Int32(outHeight), srcPointer, 1, desPointer, 1)
                }
                
                // Transposed bottom (original right)
                for i in 0..<right {
                    let srcPointer = tmpArrPointer.advanced(by: outHeight * (left + width - 1))
                    let desPointer = tmpArrPointer.advanced(by: outHeight * (left + width) + i * outHeight)
                    cblas_scopy(Int32(outHeight), srcPointer, 1, desPointer, 1)
                }
                
                // Transpose back
                vDSP_mtrans(tmpArrPointer, 1, outPlanePointer, 1, vDSP_Length(outHeight), vDSP_Length(outWidth))
            }
        }
        
        return outArr
    }
}

func add(_ a: MLMultiArray, _ b: MLMultiArray) -> MLMultiArray {
    
    assert(a.shape == b.shape)
    assert(a.dataType == .float32)
    assert(b.dataType == .float32)
    let c = try! MLMultiArray(shape: a.shape, dataType: .float32)
    
    let aArr = a.toArray()
    let bArr = b.toArray()
    
    vDSP_vadd(
        aArr, 1,
        bArr, 1,
        c.dataPointer.assumingMemoryBound(to: Float32.self), 1, vDSP_Length(a.count)
    )
    return c
}

func +(left: MLMultiArray, right: MLMultiArray) -> MLMultiArray {
    return add(left, right)
}

func stack(_ a: MLMultiArray, _ b: MLMultiArray) -> MLMultiArray {
    
    assert(a.shape == b.shape)
    let nDims = a.shape.count
    
    let aArr = a.toArray()
    let bArr = b.toArray()
    let cArr = aArr + bArr
    
    let firstLargeDimIdx = a.shape.firstIndex { $0.intValue > 1 }
    let stackDimIdx = firstLargeDimIdx ?? (nDims - 1)
    var newShape = Array(a.shape)
    newShape[stackDimIdx] = (2 * newShape[stackDimIdx].intValue) as NSNumber
    
    return MLMultiArray.fromArray(cArr, shape: newShape)
}
