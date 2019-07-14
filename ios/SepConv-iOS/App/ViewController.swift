//
//  ViewController.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-11.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import UIKit
import CoreML


class ViewController: UIViewController {
    
    @IBOutlet private weak var leftImageView: UIImageView!
    @IBOutlet private weak var rightImageView: UIImageView!
    @IBOutlet private weak var centerImageView: UIImageView!
    
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var progressView: UIProgressView!
    
    @IBOutlet private weak var startStopButton: UIButton!
    @IBOutlet private weak var importButton: UIButton!
    @IBOutlet private weak var exportButton: UIButton!
    
    private var videoWriter: VideoWriter?
    private var videoReader: VideoReader?
    private var selectedVideoURL: URL?
    
    var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private enum State {
        case idle, imported, completed, processing
    }
    
    private var state: State = .idle

    override func viewDidLoad() {
        super.viewDidLoad()
        update(for: .idle)
    }
    
    private func update(for state: ViewController.State, progress: Float? = nil) {
        switch state {
        case .idle:
            leftImageView.image = nil
            rightImageView.image = nil
            centerImageView.image = nil
            startStopButton.setTitle("Start", for: .init(rawValue: 0))
            exportButton.isEnabled = false
            importButton.isEnabled = true
            startStopButton.isEnabled = false
            progressView.progress = 0
            statusLabel.text = "Import a video to begin."
            selectedVideoURL = nil
        case .completed:
            startStopButton.setTitle("Restart", for: .init(rawValue: 0))
            exportButton.isEnabled = true
            importButton.isEnabled = true
            startStopButton.isEnabled = true
            progressView.progress = 1
            statusLabel.text = "Done."
        case .imported:
            startStopButton.setTitle("Start", for: .init(rawValue: 0))
            exportButton.isEnabled = false
            importButton.isEnabled = true
            startStopButton.isEnabled = true
            progressView.progress = 0
            statusLabel.text = "Imported. Tap on \"Start\" to begin."
        case .processing:
            startStopButton.setTitle("Stop", for: .init(rawValue: 0))
            exportButton.isEnabled = false
            importButton.isEnabled = false
            startStopButton.isEnabled = true
            progressView.progress = progress ?? 0
            statusLabel.text = "Processing. \((progress ?? 0) * 100)% done."
        }
        self.state = state
    }
    
    @IBAction func startStopPressed(_ sender: Any? = nil) {
        if state == .processing {
            stopInterpolation()
        } else {
            startInterpolation()
        }
    }
    
    @IBAction func importPressed(_ sender: Any? = nil) {
        // TODO: ask to pick video
        // ...
        
        selectedVideoURL = Bundle.main.url(forResource: "testVideo1", withExtension: "mov")!
        update(for: .imported)
    }
    
    @IBAction func exportPressed(_ sender: Any? = nil) {
        // TODO: export video
        // ...
    }
    
    private func stopInterpolation() {
        videoWriter?.cancelWriting()
        videoWriter = nil
        videoReader = nil
        update(for: .idle)
    }
    
    private func startInterpolation() {
        
        guard let selectedVideoURL = selectedVideoURL, state != .processing else {
            return
        }
        
        update(for: .processing)
        
        let network = SepConvNetwork()
        do {
            try network.prepare()
        } catch {
            print("Error while preparing!", error)
            return
        }
        
        videoReader = VideoReader(url: selectedVideoURL)
        guard let videoReader = videoReader else { return }
        
        let nFrames = videoReader.numberOfFrames
        let nInterps = nFrames?.advanced(by: -1)
        var nDone = 0
        
        let outputFrameRate = videoReader.frameRate! * 2
        let outputURL = documentsDirectory.appendingPathComponent("output_video.mp4")
        try? FileManager().removeItem(at: outputURL)
        
        DispatchQueue(label: "interpolationQueue").async { [weak self] in
            while videoReader.done == false {
                if let (rawA, rawB) = try? videoReader.nextFrameCouple() {
                    
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
                    
                    if nDone == 0 {
                        let outputFrameSize = CGSize(width: res.width, height: res.height)
                        self?.videoWriter = try! VideoWriter(url: outputURL, frameSize: outputFrameSize, frameRate: Int(outputFrameRate))
                        self?.videoWriter?.startWriting()
                    }
                    
                    self?.videoWriter?.enqueueFrame(frameA)
                    self?.videoWriter?.enqueueFrame(res)
                    self?.videoWriter?.enqueueFrame(frameB)
                    
                    nDone += 1
                    var progress: Float?
                    if let total = nInterps {
                        progress = Float(nDone) / Float(total)
                    }
                    
                    DispatchQueue.main.sync {
                        if self?.videoWriter != nil {
                            self?.leftImageView.image = UIImage(cgImage: frameA)
                            self?.centerImageView.image = UIImage(cgImage: res)
                            self?.rightImageView.image = UIImage(cgImage: frameB)
                            self?.update(for: .processing, progress: progress)
                        }
                    }
                    
                } else {
                    print("Error!")
                }
                
                if self?.videoWriter == nil || self?.videoWriter?.cancelled == true {
                    break
                }
            }
            
            if self?.videoWriter == nil || self?.videoWriter?.cancelled == true {
                DispatchQueue.main.sync {
                    self?.update(for: .idle)
                }
            }
            
            if let writer = self?.videoWriter, writer.cancelled == false {
                writer.finishWriting()
                DispatchQueue.main.sync {
                    self?.update(for: .completed)
                }
            }
        }
    }
}
