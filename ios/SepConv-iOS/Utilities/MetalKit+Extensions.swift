//
//  MetalKit+Extensions.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-14.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import MetalKit
import CoreML


extension MTLBuffer {
    
    func toMLMultiArray(_ array: MLMultiArray) {
        assert(array.byteCount == length)
        array.dataPointer.copyMemory(from: contents(), byteCount: length)
    }
    
    func toMLMultiArray(shape: [NSNumber], dataType: MLMultiArrayDataType) throws -> MLMultiArray {
        let res = try MLMultiArray(shape: shape, dataType: dataType)
        toMLMultiArray(res)
        return res
    }
    
    func update(from array: MLMultiArray) {
        self.contents().copyMemory(from: array.dataPointer, byteCount: length)
    }
}
