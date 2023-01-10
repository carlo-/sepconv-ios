//
//  ViewController.swift
//  SepConv-iOS
//
//  Created by Carlo Rapisarda on 2019-07-11.
//  Copyright © 2019 Carlo Rapisarda. All rights reserved.
//

import UIKit
import CoreML
import AVFoundation
import Photos
import MobileCoreServices


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
	private var selectedNetworkSize: SepConvNetworkSize = .x512
	
	private lazy var imagePickerController: UIImagePickerController = {
		let picker = UIImagePickerController()
		picker.sourceType = .photoLibrary
		picker.delegate = self
		picker.mediaTypes = ["public.video", "public.movie"]
		return picker
	}()
	
	var documentsDirectory: URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		return paths[0]
	}
	
	var outputURL: URL {
		return documentsDirectory.appendingPathComponent("output_video.mp4")
	}
	
	private enum State {
		case idle, imported, completed, processing
	}
	
	private struct ProgressReport {
		let progress: Float
		let rate: Double
		let timeRemaining: TimeInterval
		
		init(done: Int, total: Int, tick: DispatchTime) {
			precondition(done >= 0 && total > 0)
			precondition(done <= total)
			
			let progress = Float(done) / Float(total)
			let elapsed = tick.secondsUpToNow
			let rate = Double(done) / elapsed
			let remaining = Double(total - done) / rate
			
			self = .init(
				progress: progress,
				rate: rate,
				timeRemaining: remaining
			)
		}
		
		init(progress: Float, rate: Double, timeRemaining: TimeInterval) {
			self.progress = progress
			self.rate = rate
			self.timeRemaining = timeRemaining
		}
		
		var description: String {
			let roundedRate = round(rate * 10) / 10
			return "\(Int(progress * 100))% done. \(roundedRate) FPS. \(Int(timeRemaining))s remaining."
		}
	}
	
	private var state: State = .idle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		update(for: .idle)
	}
	
	private func update(for state: ViewController.State, report: ProgressReport? = nil) {
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
			progressView.progress = report?.progress ?? 0
			statusLabel.text = "Processing. \(report?.description ?? "")"
		}
		self.state = state
	}
	
	@IBAction func setResolutionPressed(_ sender: Any? = nil) {
		
		weak var wself = self
		let current = selectedNetworkSize
		let sheet = UIAlertController(
			title: "Select Network Size",
			message: "Maximum Image Size = Network Size - Filter Size",
			preferredStyle: .actionSheet
		)
		
		SepConvNetworkSize.allCases.forEach { size in
			let title = (current == size ? "→ " : "") + size.description + (current == size ? " ←" : "")
			sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
				wself?.selectedNetworkSize = size
			})
		}
		
		sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(sheet, animated: true)
	}
	
	@IBAction func startStopPressed(_ sender: Any? = nil) {
		if state == .processing {
			stopInterpolation()
		} else {
			startInterpolation()
		}
	}
	
	@IBAction func importPressed(_ sender: Any? = nil) {
		present(imagePickerController, animated: true)
	}
	
	@IBAction func exportPressed(_ sender: Any? = nil) {
		exportResultViaShareSheet()
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
		
		let network = SepConvNetwork(size: selectedNetworkSize)
		do {
			try network.prepare()
		} catch {
			print("Error while preparing!", error)
			return
		}
		
		videoReader = VideoReader(url: selectedVideoURL)
		guard let videoReader = videoReader else { return }
		
		let tick = DispatchTime.now()
		let nFrames = videoReader.numberOfFrames
		let nInterps = nFrames?.advanced(by: -1)
		var nDone = 0
		
		let outputFrameRate = videoReader.frameRate! * 2
		let outputURL = self.outputURL
		try? FileManager().removeItem(at: outputURL)
		
		print("""
		Starting interpolation with:
			· Input frames: \(nFrames?.description ?? "?")
			· Output frames: \(nFrames?.advanced(by: nInterps ?? 0).description ?? "?")
			· Input frame rate: \(videoReader.frameRate?.description ?? "?")
			· Output frame rate: \(outputFrameRate)
			· Num. interpolations: \(nInterps?.description ?? "?")
		""")
		
		DispatchQueue(label: "interpolationQueue").async { [weak self] in
			while videoReader.done == false {
				autoreleasepool {
					
					let rawFrames: (CGImage, CGImage)?
					
					do {
						rawFrames = try videoReader.nextFrameCouple()
					} catch {
						print("Error: nextFrameCouple() failed. Details: \(error.localizedDescription)")
						return
					}
					
					if let (rawA, rawB) = rawFrames {
						
						let frameA: CGImage
						let frameB: CGImage
						let res: CGImage
						
						do {
							frameA = try network.preprocess(frame: rawA)
							frameB = try network.preprocess(frame: rawB)
							res = try network.interpolate(frameA: frameA, frameB: frameB)
						} catch {
							print("Error: interpolation failed. Details: \(error.localizedDescription)")
							return
						}
						
						if nDone == 0 {
							let outputFrameSize = CGSize(width: res.width, height: res.height)
							self?.videoWriter = try! VideoWriter(url: outputURL, frameSize: outputFrameSize, frameRate: Int(outputFrameRate))
							self?.videoWriter?.startWriting()
							self?.videoWriter?.enqueueFrame(frameA)
						}
						
						self?.videoWriter?.enqueueFrame(res)
						self?.videoWriter?.enqueueFrame(frameB)
						
						nDone += 1
						var report: ProgressReport?
						if let total = nInterps {
							report = ProgressReport(done: nDone, total: total, tick: tick)
						}
						
						DispatchQueue.main.sync {
							if self?.videoWriter != nil {
								self?.leftImageView.image = UIImage(cgImage: frameA)
								self?.centerImageView.image = UIImage(cgImage: res)
								self?.rightImageView.image = UIImage(cgImage: frameB)
								self?.update(for: .processing, report: report)
							}
						}
						
					} else {
						print("nextFrameCouple() returned nil.")
					}
					
					if self?.videoWriter == nil || self?.videoWriter?.cancelled == true {
						return
					}
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

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	
	func imagePickerController(_ picker: UIImagePickerController,
							   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
		
		//        let loadingAlert = UIAlertController(title: "Loading...", message: nil, preferredStyle: .alert)
		let errorAlert = UIAlertController(title: "Oops!", message: nil, preferredStyle: .alert)
		errorAlert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: { _ in
			picker.dismiss(animated: true)
		}))
		
		guard let mediaType = info[.mediaType] as? String,
			  (mediaType == (kUTTypeVideo as String) || mediaType == (kUTTypeMovie as String)) else {
			errorAlert.message = "Video format not supported."
			picker.present(errorAlert, animated: true)
			return
		}
		
		guard let mediaURL = info[.mediaURL] as? URL  else {
			errorAlert.message = "Something went wrong."
			picker.present(errorAlert, animated: true)
			return
		}
		
		selectedVideoURL = mediaURL
		picker.dismiss(animated: true) { [weak self] in
			self?.update(for: .imported)
		}
		
		// This should be the proper way, but it doesn't seem to work...
		
		//        picker.present(loadingAlert, animated: true)
		//
		//        let options = PHVideoRequestOptions()
		//        options.version = .original
		//
		//        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] asset, audioMix, info in
		//            DispatchQueue.main.async {
		//                if let url = (asset as? AVURLAsset)?.url {
		//                    self?.selectedVideoURL = url
		//                    self?.update(for: .imported)
		//                    loadingAlert.dismiss(animated: true) {
		//                        picker.dismiss(animated: true)
		//                    }
		//                } else {
		//                    errorAlert.message = "Something went wrong!"
		//                    loadingAlert.dismiss(animated: true) {
		//                        picker.present(errorAlert, animated: true)
		//                    }
		//                }
		//            }
		//        }
	}
}

extension ViewController {
	
	func exportResultViaShareSheet() {
		let activityVC = UIActivityViewController(activityItems: [outputURL], applicationActivities: nil)
		present(activityVC, animated: true)
	}
	
	func exportResultToLibrary() {
		
		let outputURL = self.outputURL
		
		let loadingAlert = UIAlertController(title: "Loading...", message: nil, preferredStyle: .alert)
		
		let errorAlert = UIAlertController(title: "Oops!", message: nil, preferredStyle: .alert)
		errorAlert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
		
		let successAlert = UIAlertController(title: "Success!", message: nil, preferredStyle: .alert)
		successAlert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
		
		present(loadingAlert, animated: true)
		
		PHPhotoLibrary.requestAuthorization { [weak self] status in
			
			guard status == .authorized else {
				loadingAlert.dismiss(animated: true) {
					errorAlert.message = "App not authorized to access the photo library."
					self?.present(errorAlert, animated: true)
				}
				return
			}
			
			PHPhotoLibrary.shared().performChanges({
				PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
			}) { success, error in
				DispatchQueue.main.async {
					loadingAlert.dismiss(animated: true) {
						
						if success {
							self?.present(successAlert, animated: true)
						} else {
							errorAlert.message = error?.localizedDescription ?? "Something went wrong!"
							self?.present(errorAlert, animated: true)
						}
					}
				}
			}
		}
	}
}

private extension DispatchTime {
	
	var uptimeSeconds: TimeInterval {
		return Double(uptimeNanoseconds) / 1_000_000_000
	}
	
	func seconds(since time: DispatchTime) -> TimeInterval {
		return self.uptimeSeconds - time.uptimeSeconds
	}
	
	func seconds(upTo time: DispatchTime) -> TimeInterval {
		return time.uptimeSeconds - self.uptimeSeconds
	}
	
	var secondsUpToNow: TimeInterval {
		return seconds(upTo: .now())
	}
}
