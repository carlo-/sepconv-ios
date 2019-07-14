import torch
from onnx_coreml import convert as convert_to_coreml

import _sepconv
from src.model import Net
from src.config import OUTPUT_1D_KERNEL_SIZE


class DummySeparableConvolution(torch.nn.Module):
    def __init__(self):
        super(DummySeparableConvolution, self).__init__()

    def forward(self, im, vertical, horizontal):
        return [im, horizontal, vertical]


def load_pretrained_model(file_path):
    return Net.from_file(file_path)


def model_to_onnx(model: Net, output_file: str, input_side: int = 256, batch_size: int = 1, channels: int = 3):

    if not output_file.endswith('.onnx'):
        output_file += '.onnx'

    input_depth = channels * 2
    dummy_input = torch.randn(batch_size, input_depth, input_side, input_side, device='cpu')

    # Replace separable convolution with dummy. Actual operation implemented with Metal.
    model.separable_conv = DummySeparableConvolution()

    # Disable align_corners of upsampling modules (not supported by ONNX).
    model.upsamp.align_corners = False

    input_names = ['input_frames']
    output_names = ['padded_i2', 'k2v', 'k2h', 'padded_i1', 'k1v', 'k1h']

    torch.onnx.export(model, dummy_input, output_file, verbose=True,
                      input_names=input_names, output_names=output_names)


def onnx_to_coreml(onnx_file: str, output_file: str):

    if not output_file.endswith('.mlmodel'):
        output_file += '.mlmodel'

    # Had to modify code! See _convert_upsample in onnx_coreml/_operators.py
    mlmodel = convert_to_coreml(onnx_file)
    mlmodel.author = "Carlo Rapisarda (original implementation from Simon Niklaus and others)."
    mlmodel.license = "For academic purposes only (see README)."
    mlmodel.short_description = 'CoreML implementation of "Video Frame Interpolation via Adaptive Separable Convolution".'
    mlmodel.save(output_file)


def main():
    input_side = 1024 # should be a power of 2, minimum 128
    model_name = "SepConvPartialNetwork"
    torch_model_path = '../../models/pretrained.pth'

    max_img_side = input_side - OUTPUT_1D_KERNEL_SIZE
    print(f'Maximum input image size: {max_img_side}x{max_img_side}')

    print('Loading trained model...')
    model = load_pretrained_model(torch_model_path)

    print('Converting to ONNX...')
    onnx_path = f'./out/{model_name}{input_side}.onnx'
    model_to_onnx(model, onnx_path, input_side=input_side)

    print('Converting to CoreML...')
    mlmodel_path = f'./out/{model_name}{input_side}.mlmodel'
    onnx_to_coreml(onnx_path, mlmodel_path)


if __name__ == '__main__':
    main()
