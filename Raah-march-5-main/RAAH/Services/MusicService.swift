import Foundation
import MusicKit
import AVFoundation

final class MusicService {

    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    // MARK: - Playback

    func play(query: String) async -> String {
        guard isAuthorized else {
            dlog("Music", "Not authorized")
            return "Apple Music not authorized."
        }

        do {
            dlog("Music", "Searching: \(query)")
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            dlog("Music", "Results: \(response.songs.count) songs")

            guard let first = response.songs.first else {
                dlog("Music", "No results for: \(query)")
                return "Couldn't find '\(query)' on Apple Music."
            }

            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: response.songs, startingAt: first)
            dlog("Music", "Playing: \(first.title) by \(first.artistName)")
            try await player.play()
            return "Playing '\(first.title)' by \(first.artistName)."

        } catch {
            dlog("Music", "ERROR: \(error)")
            return "Playback failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        ApplicationMusicPlayer.shared.pause()
    }

    func stop() {
        ApplicationMusicPlayer.shared.stop()
    }

    func skipToNext() async {
        try? await ApplicationMusicPlayer.shared.skipToNextEntry()
    }

    var isPlaying: Bool {
        ApplicationMusicPlayer.shared.state.playbackStatus == .playing
    }

    var nowPlayingTitle: String? {
        guard let entry = ApplicationMusicPlayer.shared.queue.currentEntry else { return nil }
        switch entry.item {
        case .song(let song): return "\(song.title) — \(song.artistName)"
        default:              return nil
        }
    }
}
