import SwiftUI
import AVKit
import AVFoundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }

    /// State of the external-subtitle feature, surfaced in the picker.
    enum SubtitleStatus: Equatable {
        case unconfigured            // no OpenSubtitles API key
        case idle                    // options available, none playing
        case searching
        case loading                 // downloading a chosen track
        case active(String)          // language label of the playing track
        case empty                   // searched, nothing found
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var currentCue: String = ""
    @Published private(set) var subtitleOptions: [OpenSubtitleItem] = []
    @Published private(set) var subtitleStatus: SubtitleStatus
    @Published private(set) var activeFileId: Int?

    // Transport state, driven by the player so our custom controls can reflect it.
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    let player = AVPlayer()

    private let context: PlayerContext
    private weak var plex: PlexStore?
    private var playable: PlexPlayable?

    private var cues: [SubtitleCue] = []
    private var lastCueIndex = 0
    private var timeObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var timeControlCancellable: AnyCancellable?
    private var torndown = false
    private var subtitleGeneration = 0

    init(context: PlayerContext) {
        self.context = context
        subtitleStatus = OpenSubtitlesService.isConfigured ? .idle : .unconfigured
    }

    var title: String { context.title }
    var subtitlesConfigured: Bool { OpenSubtitlesService.isConfigured }

    // MARK: Lifecycle

    func start(plex: PlexStore) async {
        self.plex = plex
        guard !torndown else { return }
        configureAudioSession()

        guard let playable = await plex.resolvePlayable(context.match) else {
            if !torndown { phase = .failed(String(localized: "无法连接到 Plex 服务器或解析媒体文件")) }
            return
        }
        // The view may have been dismissed while resolving; release the
        // freshly-created transcode session instead of leaking it.
        guard !torndown else {
            await plex.stopPlayback(playable)
            return
        }
        self.playable = playable

        let item = AVPlayerItem(url: playable.url)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        duration = playable.durationSeconds ?? 0
        installTimeObserver()
        observeTimeControl()
        player.play()

        if subtitlesConfigured { await loadSubtitleOptions() }
    }

    func teardown() async {
        torndown = true
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        statusCancellable = nil
        timeControlCancellable = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let playable, let plex { await plex.stopPlayback(playable) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Subtitles

    func loadSubtitleOptions() async {
        subtitleGeneration += 1
        let generation = subtitleGeneration
        subtitleStatus = .searching
        do {
            let langs = ["zh-cn", "zh-tw", "en"]
            let items: [OpenSubtitleItem]
            if context.mediaType == .movie {
                items = try await OpenSubtitlesService.shared.search(
                    tmdbId: context.tmdbId, imdbId: context.imdbId, query: nil,
                    isMovie: true, languages: langs)
            } else {
                items = try await OpenSubtitlesService.shared.search(
                    tmdbId: context.tmdbId, imdbId: nil, query: context.title,
                    isMovie: false, languages: langs)
            }
            guard generation == subtitleGeneration else { return }  // superseded
            subtitleOptions = items
            if items.isEmpty {
                subtitleStatus = .empty
                return
            }
            subtitleStatus = .idle
            // Auto-load the most-downloaded Chinese track, else the top result.
            let best = items.first { $0.language.lowercased().hasPrefix("zh") } ?? items.first
            if let best { await selectSubtitle(best) }
        } catch {
            guard generation == subtitleGeneration else { return }
            subtitleStatus = .failed(message(error, fallback: String(localized: "字幕搜索失败")))
        }
    }

    func selectSubtitle(_ item: OpenSubtitleItem) async {
        subtitleGeneration += 1
        let generation = subtitleGeneration
        subtitleStatus = .loading
        do {
            let downloaded = try await OpenSubtitlesService.shared.downloadCues(fileId: item.fileId)
            guard generation == subtitleGeneration else { return }  // a newer choice won
            cues = downloaded
            lastCueIndex = 0
            activeFileId = item.fileId
            subtitleStatus = .active(item.languageLabel)
            refreshCue()
        } catch {
            guard generation == subtitleGeneration else { return }
            subtitleStatus = .failed(message(error, fallback: String(localized: "字幕加载失败")))
        }
    }

    func disableSubtitles() {
        subtitleGeneration += 1   // drop any in-flight download
        cues = []
        lastCueIndex = 0
        currentCue = ""
        activeFileId = nil
        subtitleStatus = subtitleOptions.isEmpty
            ? (subtitlesConfigured ? .empty : .unconfigured)
            : .idle
    }

    // MARK: Cue syncing

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // The observer is pinned to the main queue, so we're on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = seconds }
                if self.duration <= 0, let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateCue(at: seconds)
            }
        }
    }

    private func observeTimeControl() {
        timeControlCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = (status == .playing) }
    }

    // MARK: Transport

    func togglePlayPause() {
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    func skip(_ delta: Double) { seek(to: currentTime + delta) }

    func seek(to seconds: Double) {
        let upperBound = duration > 0 ? duration : seconds
        let clamped = max(0, min(seconds, upperBound))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    /// O(1) amortised forward scan with a cached index; resets on backward seek.
    private func updateCue(at seconds: Double) {
        guard seconds.isFinite, !cues.isEmpty else { setCue(""); return }
        var i = min(lastCueIndex, cues.count - 1)
        if cues[i].start > seconds { i = 0 }                          // seeked back
        while i + 1 < cues.count && cues[i + 1].start <= seconds { i += 1 }
        lastCueIndex = i
        let cue = cues[i]
        setCue(cue.contains(seconds) ? cue.text : "")
    }

    private func setCue(_ text: String) {
        if text != currentCue { currentCue = text }
    }

    private func refreshCue() {
        lastCueIndex = 0
        updateCue(at: player.currentTime().seconds)
    }

    // MARK: Player item status

    private func observeStatus(of item: AVPlayerItem) {
        statusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    if self.phase != .ready { self.phase = .ready }
                case .failed:
                    self.phase = .failed(item.error?.localizedDescription ?? String(localized: "无法播放该媒体"))
                default:
                    break
                }
            }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func message(_ error: Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
