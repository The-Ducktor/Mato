//
//  AudioPlayerService.swift
//  Mato
//
//  Audio playback service for playing media files
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor
class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()
    
    @Published var currentlyPlayingURL: URL?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    
    private init() {}
    
    /// Check if a file type is playable audio/video
    func isPlayableMedia(_ item: DirectoryItem) -> Bool {
        let audioTypes: [UTType] = [
            .audio,
            .mp3,
            .mpeg4Audio,
            .wav,
            .aiff,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .video
        ]
        
        return audioTypes.contains { item.fileType.conforms(to: $0) }
    }
    
    /// Play or pause audio file
    func togglePlayback(for url: URL) {
        // If this is the current file (playing or paused)
        if currentlyPlayingURL == url {
            if isPlaying {
                // Pause it
                pause()
            } else {
                // Resume playback
                resume()
            }
            return
        }
        
        // If currently playing/paused a different file, stop it first
        if currentlyPlayingURL != nil {
            stop()
        }
        
        // Start playing the new file
        play(url: url)
    }
    
    /// Play audio file
    private func play(url: URL) {
        do {
            // Check if file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Audio file not found: \(url.path)")
                return
            }
            
            // Create and configure audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            currentlyPlayingURL = url
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            
            // Start progress timer
            startProgressTimer()
            
            // Set up completion handler
            audioPlayer?.delegate = AudioPlayerDelegate.shared
            AudioPlayerDelegate.shared.completionHandler = { [weak self] in
                Task { @MainActor in
                    self?.stop()
                }
            }
        } catch {
            print("Failed to play audio: \(error.localizedDescription)")
            stop()
        }
    }
    
    /// Pause current playback
    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        // Keep timer running to maintain current time
        // Don't stop the timer so progress persists
    }
    
    /// Resume playback from paused state
    private func resume() {
        guard let player = audioPlayer else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }
    
    /// Stop and clear current playback
    func stop() {
        stopProgressTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
    
    /// Start the progress timer
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }
    }
    
    /// Stop the progress timer
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate Helper
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = AudioPlayerDelegate()
    var completionHandler: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completionHandler?()
    }
}
