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
    
    var nominalFrameDuration: CMTime? {
        if let frameRate = frameRate {
            return CMTime(value: 10_000, timescale: CMTimeScale(frameRate * 10_000))
        }
        return nil
    }
    
    var minFrameDuration: CMTime? {
        return videoTrack?.minFrameDuration
    }
    
    var videoDuration: Double {
        return asset.duration.seconds
    }
    
    var numberOfFrames: Int? {
        if let rate = frameRate {
           return Int(videoDuration * Double(rate)) + 1
        }
        return nil
    }
    
    var done: Bool {
        if currentTime.isValid {
            return (currentTime.seconds >= videoDuration ||
                    nextTime.seconds > videoDuration)
        }
        return false
    }
    
    var canReadSequentially: Bool {
        return nominalFrameDuration != nil
    }
    
    private var nextTime: CMTime {
        return CMTimeAdd(currentTime, nominalFrameDuration ?? .zero)
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
        currentTime = nextTime
    }
    
    func seek() {
        currentTime = .invalid
    }
    
    func currentFrame() -> CGImage? {
        return latestFrame
    }
    
    @discardableResult
    func nextFrame() throws -> CGImage? {
        if currentTime.isValid == false {
            currentTime = .zero
        } else if done {
            return nil
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
            return (a, b!)
        }
        return nil
    }
}
