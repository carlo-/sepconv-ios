//
//  ViewController.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-11.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import UIKit
import CoreML

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let documentsDirectory = paths[0]
    return documentsDirectory
}

class ViewController: UIViewController {
    
    @IBOutlet private weak var leftImageView: UIImageView!
    @IBOutlet private weak var rightImageView: UIImageView!
    @IBOutlet private weak var centerImageView: UIImageView!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var slider: UISlider!
    
    private var rightImage: UIImage!
    private var leftImage: UIImage!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let network = SepConvNetwork()
        do {
            try network.prepare()
        } catch {
            print("Error while preparing!", error)
        }
        
        let videoURL = Bundle.main.url(forResource: "testVideo1", withExtension: "mov")!
        let reader = VideoReader(url: videoURL)
        
        let outputFrameRate = reader.frameRate! * 2
        let outputURL = getDocumentsDirectory().appendingPathComponent("testVideo1_out.mp4")
        try? FileManager().removeItem(at: outputURL)
        
        var writer: VideoWriter?
        
        DispatchQueue(label: "reader").async {
            while reader.done == false {
                if let (rawA, rawB) = try? reader.nextFrameCouple() {
                    
                    let frameA: CGImage
                    let frameB: CGImage
                    let res: CGImage
                    
                    do {
                        frameA = try network.preprocess(frame: rawA)
                        frameB = try network.preprocess(frame: rawB)
                        res = try network.interpolate(frameA: frameA, frameB: frameB)
                    } catch {
                        print("Error!", error)
                        break
                    }
                    
                    if writer == nil {
                        let outputFrameSize = CGSize(width: res.width, height: res.height)
                        writer = try! VideoWriter(url: outputURL, frameSize: outputFrameSize, frameRate: Int(outputFrameRate))
                        writer?.startWriting()
                    }
                    
                    writer?.enqueueFrame(frameA)
                    writer?.enqueueFrame(res)
                    writer?.enqueueFrame(frameB)
                    
                    DispatchQueue.main.sync {
                        self.leftImageView.image = UIImage(cgImage: frameA)
                        self.centerImageView.image = UIImage(cgImage: res)
                        self.rightImageView.image = UIImage(cgImage: frameB)
                    }
                    
                } else {
                    print("Error!")
                }
            }
            
            writer?.finishWriting()
        }
        
        return;
        
//        let videoURL = Bundle.main.url(forResource: "testVideo1", withExtension: "mov")!
//        let reader = VideoReader(url: videoURL)
//
//        DispatchQueue(label: "reader").async {
//            while reader.done == false {
//                if let frame = try? reader.nextFrame() {
//                    let image = UIImage(cgImage: frame)
//
//                    print("hey")
//
//                    DispatchQueue.main.sync {
//                        self.centerImageView.image = image
//                    }
//
//                } else {
//                    print("Error!")
//                }
//            }
//        }
//
//        return;
        
        
//        let r = MLMultiArray.arange([1, 1, 1, 4, 5])
//        r.prettyPrint()
//
//        let repl = r.replicationPad2D(left: 2, right: 3, top: 4, bottom: 5)
//        repl.prettyPrint()
//
//        let trimmed = repl.trim2D(left: 0, right: 1, top: 5, bottom: 59)
//        trimmed.prettyPrint()
//
//        return;
        
//        print("Building...")
//        let r = MLMultiArray.arange([1, 1, 34, 642, 213])
//
//        print("Padding...")
//        let repl = r.replicationPad(left: 67, right: 67, top: 67, bottom: 67)
//
//        print("Done.", r.count, repl.count)
//        return;
        
//        let img = UIImage(named: "right256")!
//        let r = MLMultiArray.fromImage(img)!
//        let repl = r.replicationPad2D(left: 20, right: 50, top: 20, bottom: 70)
//        let back = repl.toUIImage()
//        centerImageView.image = back
        
//        return;
        
        
//        rightImage = #imageLiteral(resourceName: "left256")
//        leftImage = #imageLiteral(resourceName: "right256")
        
        
//        sliderValueChanged()
//
//        let model = SepConvModel()
//
//        do {
//            try model.prepare()
//        } catch {
//            print("Error while preparing!", error)
//        }
//
//        let tic = DispatchTime.now().uptimeNanoseconds
//
//        DispatchQueue(label: "some").async { [unowned self] in
//
//            for i in 0..<1_000_000 {
//
//                let res: UIImage?
//                do {
//                    res = try model.forward(frameA: self.leftImage, frameB: self.rightImage)
//                } catch {
//                    print("Error!", error)
//                    res = nil
//                }
//
//                let time = Double(DispatchTime.now().uptimeNanoseconds - tic) / 1_000_000_000
//                let status = "Done \(i) (\(Double(i+1)/time) FPS)"
//
//                DispatchQueue.main.sync {
//                    self.centerImageView.image = res
//                    self.statusLabel.text = status
//                    print(status)
//                }
//            }
//        }
        
//        let img = #imageLiteral(resourceName: "right256")
//        let arr = MLMultiArray.fromImage(img)
//        let imgBack = arr?.toUIImage()
//        centerImageView.image = imgBack
    }
    
    @IBAction func sliderValueChanged(_ sender: Any? = nil) {
        let rightSourceImage = UIImage(named: "right256")!
        let leftSourceImage = UIImage(named: "left256")!
        
        guard let rightCGImage = rightSourceImage.cgImage,
              let leftCGImage = leftSourceImage.cgImage else {
            fatalError()
        }
        
        let rightCIImage = CIImage(cgImage: rightCGImage)
        let leftCIImage = CIImage(cgImage: leftCGImage)
        
        let scale: CGFloat = 1.5
        let extraPixels = (scale - 1.0) * CGFloat(rightCGImage.width) * 0.5
        let xTransl = extraPixels * CGFloat(slider?.value ?? 0)
        
        let rTF = CGAffineTransform(translationX: xTransl, y: 0.0)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let finalRightCIImage = rightCIImage.transformed(by: rTF).transformed(by: CGAffineTransform(scaleX: 1/scale, y: 1/scale))
        
        let cgImageR = CIContext(options: nil).createCGImage(finalRightCIImage, from: rightCIImage.extent)
        rightImage = UIImage(cgImage: cgImageR!)
        rightImageView.image = rightImage
        
        let lTF = CGAffineTransform(scaleX: scale, y: scale)
        let finalLeftCIImage = leftCIImage.transformed(by: lTF).transformed(by: CGAffineTransform(scaleX: 1/scale, y: 1/scale))
        
        let cgImageL = CIContext(options: nil).createCGImage(finalLeftCIImage, from: leftCIImage.extent)
        leftImage = UIImage(cgImage: cgImageL!)
        leftImageView.image = leftImage
    }
}

