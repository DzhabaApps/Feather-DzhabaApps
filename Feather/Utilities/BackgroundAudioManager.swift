//
//  BackgroundAudioManager.swift
//  Feather
//
//  Created by Nagata Asami on 12/10/25.
//

#if !targetEnvironment(macCatalyst)

import AVFoundation

class BackgroundAudioManager {
	static let shared = BackgroundAudioManager()
	private let _engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
	

	private init() {}
	
	@discardableResult
    func start() -> Bool {
		do {
			let session = AVAudioSession.sharedInstance()
			
			try session.setCategory(.playback, options: [.mixWithOthers])
			try session.setActive(true)
            if source == nil {
			let silence = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
				let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
				for buffer in ablPointer {
					memset(buffer.mData, 0, Int(buffer.mDataByteSize))
				}
				return noErr
			}
			
			_engine.attach(silence)
			_engine.connect(silence, to: _engine.mainMixerNode, format: nil)
            source = silence
            }
			try _engine.start()
            return true
		} catch {
			print("failed to start engine:", error)
            return false
		}
	}
	
	func stop() {
		_engine.stop()
		try? AVAudioSession.sharedInstance().setActive(false)
	}
}

#endif
