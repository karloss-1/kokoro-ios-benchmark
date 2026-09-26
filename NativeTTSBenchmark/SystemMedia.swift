import MediaPlayer
import UIKit

@MainActor final class SystemMedia {
    private weak var speech: SpeechEngine?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var publishedID: UUID?
    private var artwork: MPMediaItemArtwork?
    init(speech: SpeechEngine) {
        self.speech = speech
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand) { $0.play() }
        bind(center.pauseCommand) { $0.pause() }
        bind(center.togglePlayPauseCommand) { $0.isPlaying ? $0.pause() : $0.play() }
        bind(center.stopCommand) { $0.stop() }
        // Each logical queue item is a sentence, never a pretend audio timestamp.
        bind(center.previousTrackCommand) { $0.sentence(-1) }
        bind(center.nextTrackCommand) { $0.sentence(1) }
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        update()
    }
    isolated deinit { for (command, target) in targets { command.removeTarget(target) } }
    private func bind(_ command: MPRemoteCommand, action: @escaping @MainActor @Sendable (SpeechEngine) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in if let speech = self?.speech { action(speech) } }
            return .success
        }
        targets.append((command, target))
    }
    func update() {
        let center = MPRemoteCommandCenter.shared()
        guard let speech, let id = speech.documentID, !speech.units.isEmpty, speech.state != .stopped else {
            targets.forEach { $0.0.isEnabled = false }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            publishedID = nil
            artwork = nil
            return
        }
        guard speech.isPlaying || publishedID == id else { return }
        if publishedID != id {
            publishedID = id
            artwork = nil
            Task { [weak self] in
                let data = await LibraryStorage.shared.thumbnail(id)
                guard let self, self.publishedID == id else { return }
                if let data,
                   let image = UIImage(data: data),
                   let cgImage = image.cgImage {
                    self.artwork = MPMediaItemArtwork(
                        boundsSize: image.size,
                        requestHandler: Self.artworkRequestHandler(for: cgImage)
                    )
                }
                self.updateMetadata()
            }
        }
        center.playCommand.isEnabled = !speech.isPlaying
        center.pauseCommand.isEnabled = speech.isPlaying
        center.stopCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = speech.index > 0
        center.nextTrackCommand.isEnabled = speech.index + 1 < speech.units.count
        updateMetadata()
    }
    private func updateMetadata() {
        guard let speech, publishedID == speech.documentID else { return }
        let section = speech.currentUnit.flatMap { speech.content?.sections[$0.section].title }
        let position = "Sentence \(speech.index + 1) of \(speech.units.count) · \(Int(speech.progress * 100))%"
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: speech.title,
            MPMediaItemPropertyArtist: [section, position].compactMap { $0 }.joined(separator: " · "),
            MPMediaItemPropertyAlbumTitle: "Document Reader",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: speech.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: speech.index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: speech.units.count
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        // No duration or elapsed-time keys: AVSpeechSynthesizer has no audio timeline.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// MediaPlayer can request artwork away from the main queue. Build its callback
    /// outside MainActor isolation so its execution doesn't inherit a main-queue check.
    nonisolated private static func artworkRequestHandler(for image: CGImage) -> (CGSize) -> UIImage {
        { _ in UIImage(cgImage: image) }
    }
}
