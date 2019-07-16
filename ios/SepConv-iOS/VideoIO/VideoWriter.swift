//
//  VideoWriter.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-13.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import AVFoundation
import Photos


class VideoWriter {
    
    let videoURL: URL
    let frameSize: CGSize
    let frameRate: Int
    
    var frameDuration: CMTime {
        return CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
    
    var cancelled: Bool {
        return self.assetWriter.status == .cancelled
    }
    
    private let queue: FrameQueue
    private var assetWriter: AVAssetWriter!
    private var writerInput: AVAssetWriterInput!
    
    init(url: URL, frameSize: CGSize, frameRate: Int, queueCapacity: Int = 5) throws {
        self.videoURL = url
        self.frameSize = frameSize
        self.frameRate = frameRate
        self.queue = FrameQueue(capacity: queueCapacity)
        try prepareAssetWriter()
    }
    
    private func prepareAssetWriter() throws {
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: frameSize.width,
            AVVideoHeightKey: frameSize.height,
        ]
        
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: AVFileType.mp4)
        assetWriter.add(writerInput)
    }
    
    func enqueueFrame(_ image: CGImage) {
        guard assetWriter.status == .writing || assetWriter.status == .unknown else {
            print("Writer already finished session.")
            return
        }
        queue.put(image)
    }
    
    func finishWriting() {
        self.queue.signalTermination()
    }
    
    func cancelWriting() {
        assetWriter.cancelWriting()
        self.queue.signalTermination()
    }
    
    func startWriting() {
        
        let sourceBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey: frameSize.width,
                kCVPixelBufferHeightKey: frameSize.height,
            ] as [String : Any]
        )
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        if pixelBufferAdaptor.pixelBufferPool == nil {
            fatalError("Error converting images to video: pixelBufferPool nil after starting session")
        }
        
        let dispatchQueue = DispatchQueue(label: "VideoWriterQueue")
        var currentTime = CMTime.zero
        var writtenFrames = 0
        var done = false
        
        writerInput.requestMediaDataWhenReady(on: dispatchQueue) { [weak self] in
            guard let self = self else { return }
            
            while self.writerInput.isReadyForMoreMediaData {
                
                if let frame = self.queue.pop() {
                    
                    do {
                        try pixelBufferAdaptor.append(frame, presentationTime: currentTime, bitmapInfo: sourceBitmapInfo)
                    } catch {
                        print("Error:", error.localizedDescription)
                        // TODO: Handle error
                    }
                    
                    currentTime = CMTimeAdd(currentTime, self.frameDuration)
                    writtenFrames += 1
                    
                } else {
                    done = true
                    break
                }
            }
            
            if self.cancelled {
                self.writerInput.markAsFinished()
                return
            }
            
            if done {
                self.writerInput.markAsFinished()
                self.assetWriter.finishWriting {
                    if let error = self.assetWriter.error {
                        print("Error: \(error.localizedDescription)")
                    } else {
                        print("Saved video at \(self.videoURL)")
                    }
                }
            }
        }
    }
}

private class FrameQueue {
    
    private let readerSem: DispatchSemaphore
    private let writerSem: DispatchSemaphore
    
    private let contentSem: DispatchSemaphore
    private var content: [CGImage]
    
    init(capacity: Int) {
        precondition(capacity > 0)
        self.readerSem = DispatchSemaphore(value: 0)
        self.writerSem = DispatchSemaphore(value: capacity)
        self.contentSem = DispatchSemaphore(value: 1)
        self.content = []
    }
    
    private func safePut(_ frame: CGImage) {
        contentSem.wait()
        content.append(frame)
        contentSem.signal()
    }
    
    private func safePop() -> CGImage? {
        contentSem.wait()
        let frame: CGImage?
        if content.isEmpty {
            frame = nil
        } else {
            frame = content.removeFirst()
        }
        contentSem.signal()
        return frame
    }
    
    func signalTermination() {
        readerSem.signal()
    }
    
    func put(_ frame: CGImage) {
        writerSem.wait()
        safePut(frame)
        readerSem.signal()
    }
    
    func pop() -> CGImage? {
        readerSem.wait()
        if let frame = safePop() {
            writerSem.signal()
            return frame
        }
        return nil
    }
}

private extension AVAssetWriterInputPixelBufferAdaptor {
    
    func append(_ frame: CGImage, presentationTime: CMTime, bitmapInfo: CGBitmapInfo) throws {
        
        guard let pixelBufferPool = pixelBufferPool else {
            throw NSError(domain: "Pixel buffer pool not ready.", code: -1, userInfo: nil)
        }
        
        var pixelBufferOpt: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOpt)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOpt else {
            throw NSError(domain: "Failed to allocate pixel buffer.", code: -1, userInfo: nil)
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .init(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        let context = CGContext(
            data: pixelData,
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        )
        
        guard context != nil else {
            throw NSError(domain: "Failed to initialize drawing context.", code: -1, userInfo: nil)
        }
        
        context?.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0))
        
        let result = append(pixelBuffer, withPresentationTime: presentationTime)
        if result == false {
            throw NSError(domain: "Failed to append frame to pixel buffer.", code: -1, userInfo: nil)
        }
    }
}
