//
//  VideoReader.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-13.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import AVFoundation


class VideoReader {
    
    let videoURL: URL
    let asset: AVAsset
    
    var videoTrack: AVAssetTrack? {
        return asset.tracks(withMediaType: .video).first
    }
    
    var frameRate: Float? {
        return videoTrack?.nominalFrameRate
    }
    
    var frameDuration: CMTime? {
        return videoTrack?.minFrameDuration
    }
    
    var done: Bool {
        if currentTime.isValid {
            return currentTime.seconds >= asset.duration.seconds
        }
        return false
    }
    
    private var latestFrame: CGImage?
    private var currentTime: CMTime = .invalid
    private var generator: AVAssetImageGenerator
    
    init(url: URL) {
        self.videoURL = url
        self.asset = AVAsset(url: url)
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.generator.requestedTimeToleranceAfter = .zero
        self.generator.requestedTimeToleranceBefore = .zero
    }
    
    private func advanceTime() {
        currentTime = CMTimeAdd(currentTime, frameDuration ?? .zero)
    }
    
    func seek() {
        currentTime = .invalid
    }
    
    func currentFrame() -> CGImage? {
        return latestFrame
    }
    
    @discardableResult
    func nextFrame() throws -> CGImage {
        if currentTime.isValid == false {
            currentTime = .zero
        } else {
            advanceTime()
        }
        let frame = try generator.copyCGImage(at: currentTime, actualTime: nil)
        latestFrame = frame
        return frame
    }
    
    func nextFrameCouple() throws -> (CGImage, CGImage)? {
        if latestFrame == nil {
            try nextFrame()
        }
        if done == false, let a = latestFrame {
            let b = try nextFrame()
            return (a, b)
        }
        return nil
    }
}
