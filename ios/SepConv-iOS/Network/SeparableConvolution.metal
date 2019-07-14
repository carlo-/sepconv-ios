//
//  SeparableConvolution.metal
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-11.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#define IDX_4(ARRAY, X, Y, Z, W) ((ARRAY)[((X) * (ARRAY##Stride.x)) + ((Y) * (ARRAY##Stride.y)) + ((Z) * (ARRAY##Stride.z)) + ((W) * (ARRAY##Stride.w))])


struct SepConvShaderInfo {
    int4 inputSize;
    int4 inputStride;
    
    int4 verticalSize;
    int4 verticalStride;
    
    int4 horizontalSize;
    int4 horizontalStride;
    
    int4 outputSize;
    int4 outputStride;
    
    int filterSize;
};


kernel void separable_convolution(const device float *input [[ buffer(0) ]],
                                  device float *output [[ buffer(1) ]],
                                  const device float *vertical [[ buffer(2) ]],
                                  const device float *horizontal [[ buffer(3) ]],
                                  const device SepConvShaderInfo &shader_info [[ buffer(4) ]],
                                  ushort3 gid [[thread_position_in_grid]]) {
    
    int4 inputStride = shader_info.inputStride;
    int4 verticalStride = shader_info.verticalStride;
    int4 horizontalStride = shader_info.horizontalStride;
    int4 outputSize = shader_info.outputSize;
    int filterSize = shader_info.filterSize;
    
    // FIXME: These could be removed from SepConvShaderInfo
//    int4 verticalSize = shader_info.verticalSize;
//    int4 horizontalSize = shader_info.horizontalSize;
//    int4 outputStride = shader_info.outputStride;
//    int4 inputSize = shader_info.inputSize;
//    int inputHeight = inputSize[2];
//    int inputWidth = inputSize[3];
    
    int outputHeight = outputSize[2];
    int outputWidth = outputSize[3];
    
    if (gid.x < filterSize/2 || gid.x - filterSize/2 >= outputWidth ||
        gid.y < filterSize/2 || gid.y - filterSize/2 >= outputHeight ||
        gid.z >= 3) {
        return;
    }
    
    int intBatch = 0;
    int intDepth = gid.z;
    int intY = gid.y - filterSize/2;
    int intX = gid.x - filterSize/2;

    float dblOutput = 0.0;
    
    for (int intFilterY = 0; intFilterY < filterSize; intFilterY += 1) {
        for (int intFilterX = 0; intFilterX < filterSize; intFilterX += 1) {
            dblOutput += IDX_4(input, intBatch, intDepth, intY + intFilterY, intX + intFilterX) * IDX_4(vertical, intBatch, intFilterY, intY, intX) * IDX_4(horizontal, intBatch, intFilterX, intY, intX);
        }
    }
    
    int outIndex = intX + intY * outputWidth + intDepth * outputWidth * outputHeight;
    output[outIndex] = dblOutput;
}
