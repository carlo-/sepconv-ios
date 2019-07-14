//
//  CoreGraphics+Extensions.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-14.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import CoreGraphics


extension CGImage {
    
    func resized(to targetSize: CGSize) -> CGImage? {
        
        let newBytesPerRow = Int(targetSize.width) * (bitsPerPixel / 8)
        
        let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: newBytesPerRow,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        )
        
        context?.interpolationQuality = .high
        context?.draw(self, in: CGRect(origin: .zero, size: targetSize))
        
        return context?.makeImage()
    }
    
    func resized(withMaxSide maxSide: Int) -> CGImage? {
        let targetSize: CGSize
        if width > height {
            let other = Float(height) * Float(maxSide) / Float(width)
            targetSize = CGSize(width: maxSide, height: Int(other))
        } else {
            let other = Float(width) * Float(maxSide) / Float(height)
            targetSize = CGSize(width: Int(other), height: maxSide)
        }
        return resized(to: targetSize)
    }
    
    func toRGBA() -> CGImage? {
        
        let count = width * height * 4
        var data = [UInt8](repeating: 0, count: count)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        )
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
