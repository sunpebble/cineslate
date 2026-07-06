import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var plex: PlexStore
    @Environment(\.dismiss) private var dismiss
    @State private var showKeyEditor = false
    @State private var cacheSize = 0
    @State private var isClearingCache = false
    @State private var showSubtitleEditor = false
    @State private var subtitlesConfigured = OpenSubtitlesService.isConfigured

    var body: some View {
        NavigationStack {
            ZStack {
                RFX.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        plexCard
                        subtitleCard
                        tmdbCard
                        cacheCard
                    }
                    .padding(20)
                }
                .rfxScroll()
            }
            .navigationTitle(String(localized: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成")) { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showKeyEditor) { KeyEditorView() }
            .sheet(isPresented: $showSubtitleEditor, onDismiss: {
                subtitlesConfigured = OpenSubtitlesService.isConfigured
            }) { OpenSubtitlesEditorView() }
        }
        .preferredColorScheme(.dark)
    }

    private var subtitleCard: some View {
        Button { showSubtitleEditor = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(RFX.blue)
                    .frame(width: 46, height: 46)
                    .background(RFX.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "OpenSubtitles 字幕")).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitlesConfigured ? String(localized: "已配置 · 播放时可在线加载字幕") : String(localized: "未配置 · 填写 API Key 后启用"))
                        .font(.system(size: 13)).foregroundStyle(RFX.text3)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RFX.text4)
            }
            .padding(18)
            .background(RFX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var plexCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "Plex 媒体源"), systemImage: "play.rectangle.on.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RFX.text4)

            if plex.isConnected {
                HStack(spacing: 12) {
                    plexLogo
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plex.username ?? "Plex").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        Text(String(format: String(localized: "已连接 %lld 台服务器"), plex.serverCount))
                            .font(.system(size: 13)).foregroundStyle(RFX.text3)
                    }
                    Spacer()
                    Button(String(localized: "断开")) { plex.disconnect() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0xff6b6b))
                }
            } else {
                Text(String(localized: "登录 Plex 后，详情页会显示你媒体库里实际可播的资源。"))
                    .font(.system(size: 13))
                    .foregroundStyle(RFX.text3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await plex.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if plex.isConnecting {
                            ProgressView().controlSize(.small).tint(.black)
                        } else {
                            Image(systemName: "link").font(.system(size: 14, weight: .bold))
                        }
                        Text(plex.isConnecting ? String(localized: "正在连接…") : String(localized: "连接 Plex 账号"))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(hex: 0xe5a00d), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(plex.isConnecting)

                if let error = plex.errorMessage {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xff6b6b))
                }
            }
        }
        .padding(18)
        .background(RFX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var plexLogo: some View {
        Image(systemName: "play.tv.fill")
            .font(.system(size: 18))
            .foregroundStyle(Color(hex: 0xe5a00d))
            .frame(width: 46, height: 46)
            .background(Color(hex: 0xe5a00d).opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tmdbCard: some View {
        Button { showKeyEditor = true } label: {
            HStack(spacing: 12) {
                Text("🎬").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("TMDB API Key").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(KeyStore.hasCustomTMDBKey ? String(localized: "使用自定义 Key") : String(localized: "使用内置 Key"))
                        .font(.system(size: 13)).foregroundStyle(RFX.text3)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RFX.text4)
            }
            .padding(18)
            .background(RFX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Cache

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "缓存"), systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RFX.text4)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "图片与数据缓存"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(cacheSizeText)
                        .font(.system(size: 13)).foregroundStyle(RFX.text3)
                }
                Spacer()
                Button {
                    Task { await clearCache() }
                } label: {
                    if isClearingCache {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text(String(localized: "清除"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0xff6b6b))
                    }
                }
                .disabled(isClearingCache || cacheSize == 0)
            }
        }
        .padding(18)
        .background(RFX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task { await refreshCacheSize() }
    }

    private var cacheSizeText: String {
        cacheSize == 0
            ? String(localized: "暂无缓存")
            : ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file)
    }

    private func refreshCacheSize() async {
        let images = await ImageStore.shared.diskUsageBytes()
        let data = await DiskCache.shared.diskUsageBytes()
        cacheSize = images + data
    }

    private func clearCache() async {
        isClearingCache = true
        await ImageStore.shared.clear()
        await DiskCache.shared.clear()
        await refreshCacheSize()
        isClearingCache = false
    }

}

/// TMDB API key editor — mirrors the source design's key overlay.
struct KeyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = KeyStore.tmdbKey

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("TMDB API Key").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                Text(String(localized: "在 themoviedb.org → 设置 → API 免费申请 v3 Key，粘贴后即可加载真实海报。Key 仅保存在本机。"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(RFX.text3)
                    .lineSpacing(4)
                    .padding(.top, 8)

                TextField(String(localized: "粘贴 API Key (v3 auth)"), text: $draft)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RFX.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 0.5))
                    .padding(.top, 16)

                HStack(spacing: 10) {
                    Button {
                        KeyStore.tmdbKey = AppConfig.tmdbDefaultKey
                        dismiss()
                    } label: {
                        Text(String(localized: "恢复内置")).font(.system(size: 15, weight: .bold)).foregroundStyle(RFX.text2)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RFX.cardAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button {
                        KeyStore.tmdbKey = draft
                        dismiss()
                    } label: {
                        Text(String(localized: "保存并加载")).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RFX.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            .padding(22)
            .background(RFX.sheet, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 24)
        }
        .presentationBackground(.clear)
    }
}

/// OpenSubtitles credentials editor. API Key is required; username/password are
/// optional and raise the daily download quota.
struct OpenSubtitlesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String
    @State private var username: String
    @State private var password: String

    init() {
        let config = OpenSubtitlesService.loadConfig()
        _apiKey = State(initialValue: config?.apiKey ?? "")
        _username = State(initialValue: config?.username ?? "")
        _password = State(initialValue: config?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RFX.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(String(localized: "在 opensubtitles.com 注册并在 Consumers 创建一个 API Consumer 获取 API Key。Key 与账号仅保存在本机钥匙串。"))
                            .font(.system(size: 13.5)).foregroundStyle(RFX.text3).lineSpacing(4)

                        field(String(localized: "API Key（必填）"), text: $apiKey, placeholder: String(localized: "粘贴 API Key"), secure: false)
                        field(String(localized: "用户名（可选）"), text: $username, placeholder: String(localized: "OpenSubtitles 用户名"), secure: false)
                        field(String(localized: "密码（可选）"), text: $password, placeholder: String(localized: "用于提升下载配额"), secure: true)

                        HStack(spacing: 10) {
                            Button {
                                OpenSubtitlesService.clearConfig()
                                dismiss()
                            } label: {
                                Text(String(localized: "清除")).font(.system(size: 15, weight: .bold)).foregroundStyle(RFX.text2)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RFX.cardAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            Button {
                                save()
                                dismiss()
                            } label: {
                                Text(String(localized: "保存")).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(canSave ? RFX.accent : RFX.cardAlt,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(!canSave)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                }
                .rfxScroll()
            }
            .navigationTitle("OpenSubtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "取消")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = OpenSubtitlesConfig(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            username: trimmedUser.isEmpty ? nil : trimmedUser,
            password: password.isEmpty ? nil : password
        )
        OpenSubtitlesService.saveConfig(config)
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, placeholder: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(RFX.text4)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15)).foregroundStyle(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(14)
            .background(RFX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}
