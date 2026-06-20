import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// Full-screen Plex player: a controls-less AVPlayer surface with our own glass
/// transport controls (a single control layer — not the native bar stacked under
/// ours), an OpenSubtitles overlay we render ourselves, and a subtitle picker.
struct PlayerView: View {
    let context: PlayerContext

    @EnvironmentObject private var plex: PlexStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlayerViewModel
    @State private var showSubtitlePicker = false
    @State private var showControls = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?

    init(context: PlayerContext) {
        self.context = context
        _model = StateObject(wrappedValue: PlayerViewModel(context: context))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Controls-less surface (AVPlayerLayer): our glass controls below are
            // the only control layer, so the native transport bar no longer stacks
            // under ours (the "double controls" of SwiftUI's VideoPlayer).
            PlayerSurface(player: model.player)
                .ignoresSafeArea()

            subtitleOverlay
                .allowsHitTesting(false)

            if showControls {
                controlsLayer.transition(.opacity)
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setControls(true) }
            }

            centerState
        }
        .statusBarHidden(true)
        .task { await model.start(plex: plex) }
        .onAppear { setControls(true) }
        .onDisappear { hideTask?.cancel(); Task { await model.teardown() } }
        .onChange(of: model.currentTime) { _, t in if !scrubbing { scrubValue = t } }
        .onChange(of: model.isPlaying) { _, _ in scheduleAutoHide() }
        .sheet(isPresented: $showSubtitlePicker) {
            SubtitlePickerSheet(model: model)
        }
    }

    // MARK: Controls

    private var controlsLayer: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { setControls(false) }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if model.phase == .ready { bottomBar }
            }

            if model.phase == .ready {
                HStack(spacing: 40) {
                    transportButton("gobackward.10", size: 26) { model.skip(-10); scheduleAutoHide() }
                    transportButton(model.isPlaying ? "pause.fill" : "play.fill", size: 36) {
                        model.togglePlayPause(); scheduleAutoHide()
                    }
                    transportButton("goforward.10", size: 26) { model.skip(10); scheduleAutoHide() }
                }
            }
        }
    }

    private func transportButton(_ name: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(value: $scrubValue, in: 0...max(model.duration, 1)) { editing in
                scrubbing = editing
                if editing { hideTask?.cancel() } else { model.seek(to: scrubValue); setControls(true) }
            }
            .tint(RFX.accent)

            HStack {
                Text(timeString(scrubbing ? scrubValue : model.currentTime))
                Spacer()
                Text("-" + timeString(max(model.duration - (scrubbing ? scrubValue : model.currentTime), 0)))
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: Controls visibility

    private func setControls(_ visible: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) { showControls = visible }
        scheduleAutoHide()
    }

    /// Auto-hides the controls a few seconds after they appear, while playing.
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard showControls, model.isPlaying, !scrubbing else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showControls = false }
        }
    }

    // MARK: Subtitle overlay (rendered above video, below controls)

    @ViewBuilder private var subtitleOverlay: some View {
        if !model.currentCue.isEmpty {
            VStack {
                Spacer()
                Text(model.currentCue)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 1)
                    .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 26)
                    .padding(.bottom, showControls ? 116 : 72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: showControls)
        }
    }

    // MARK: Top bar (close · title · subtitle picker)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassCircle()

            Text(model.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 4)

            Spacer(minLength: 8)

            Button { showSubtitlePicker = true; scheduleAutoHide() } label: {
                Image(systemName: model.activeFileId != nil ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.activeFileId != nil ? RFX.accent : .white)
                    .frame(width: 40, height: 40)
            }
            .glassCircle()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: Center state (loading / error)

    @ViewBuilder private var centerState: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                Text("正在连接 Plex…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(RFX.accent)
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                Button("返回") { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .buttonStyle(.glassProminent)
                    .tint(RFX.accent)
            }
        case .ready:
            EmptyView()
        }
    }
}

/// A controls-less video surface backed directly by AVPlayerLayer.
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - Subtitle picker

private struct SubtitlePickerSheet: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                RFX.bg.ignoresSafeArea()
                content
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(RFX.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch model.subtitleStatus {
        case .unconfigured:
            infoState(icon: "key.slash",
                      text: "前往「设置 → OpenSubtitles」填写 API Key 后，即可在线搜索并加载字幕。")
        case .searching:
            busyState("正在搜索字幕…")
        default:
            ScrollView {
                VStack(spacing: 10) {
                    if case .loading = model.subtitleStatus { busyRow("正在加载字幕…") }
                    if case .failed(let message) = model.subtitleStatus { errorRow(message) }

                    offRow

                    if model.subtitleOptions.isEmpty, case .empty = model.subtitleStatus {
                        infoState(icon: "text.magnifyingglass", text: "没有找到匹配的字幕。")
                            .padding(.top, 20)
                    } else {
                        ForEach(model.subtitleOptions) { option in
                            optionRow(option)
                        }
                    }
                }
                .padding(16)
            }
            .rfxScroll()
        }
    }

    private var offRow: some View {
        Button {
            model.disableSubtitles()
        } label: {
            HStack {
                Text("关闭字幕").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if model.activeFileId == nil {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(RFX.accent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RFX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func optionRow(_ option: OpenSubtitleItem) -> some View {
        Button {
            Task { await model.selectSubtitle(option) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(option.languageLabel)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        if option.hd { badge("HD", RFX.blue) }
                        if option.aiTranslated { badge("AI", RFX.purple) }
                        if option.hearingImpaired { badge("CC", RFX.text4) }
                    }
                    if !option.release.isEmpty {
                        Text(option.release)
                            .font(.system(size: 12)).foregroundStyle(RFX.text3)
                            .lineLimit(1)
                    }
                    Text("↓ \(option.downloads)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(RFX.text4)
                }
                Spacer(minLength: 8)
                if model.activeFileId == option.fileId {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(RFX.accent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RFX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(.white)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(RFX.text2)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RFX.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: 0xff6b6b))
            Text(text).font(.system(size: 13)).foregroundStyle(Color(hex: 0xff9b9b))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RFX.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func busyState(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(.white)
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(RFX.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoState(icon: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(RFX.text4)
            Text(text)
                .font(.system(size: 14)).foregroundStyle(RFX.text3)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
