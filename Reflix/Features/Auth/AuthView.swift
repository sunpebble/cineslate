import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer()
                brand
                Spacer()
                card
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(RFX.bgRoot.ignoresSafeArea())
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(hex: 0x2a1206), Color(hex: 0x140a06), .black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Text("REFLIX")
                .font(.system(size: 54, weight: .black))
                .kerning(3)
                .foregroundStyle(RFX.accentBright)
                .shadow(color: RFX.accent.opacity(0.5), radius: 20, y: 6)
            Text("发现你的下一部好剧")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RFX.text3)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Picker("", selection: $isRegister) {
                Text("登录").tag(false)
                Text("注册").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            field(icon: "envelope.fill", placeholder: "邮箱", text: $email, field: .email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)

            field(icon: "lock.fill", placeholder: "密码（至少 6 位）", text: $password, field: .password, secure: true)
                .textContentType(isRegister ? .newPassword : .password)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xff6b6b))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                ZStack {
                    if auth.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(isRegister ? "注册并登录" : "登录")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RFX.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(canSubmit ? 1 : 0.5)
            }
            .disabled(!canSubmit || auth.isWorking)
            .padding(.top, 4)
        }
        .padding(20)
        .glassRoundedRect(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       field: Field, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(RFX.text4)
                .frame(width: 20)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .focused($focus, equals: field)
            .submitLabel(field == .email ? .next : .go)
            .onSubmit {
                if field == .email { focus = .password } else { submit() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(hex: 0x0c0c0d), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let mail = email.trimmingCharacters(in: .whitespaces)
        Task {
            if isRegister {
                await auth.signUp(email: mail, password: password)
            } else {
                await auth.signIn(email: mail, password: password)
            }
        }
    }
}

/// 6 位验证码：可见格子 + 背后隐藏 TextField（支持 iOS 一次性验证码自动填充）。
private struct OTPCodeField: View {
    @Binding var code: String
    var onComplete: (String) -> Void

    @FocusState private var focused: Bool
    private let count = 6

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.001)                 // 保持可聚焦，但视觉隐藏
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(count))
                    if digits != code { code = digits }
                    if digits.count == count { onComplete(digits) }
                }

            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    box(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    private func box(at index: Int) -> some View {
        let chars = Array(code)
        let char = index < chars.count ? String(chars[index]) : ""
        let isCurrent = index == chars.count && focused
        return Text(char)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: 0x0c0c0d), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? RFX.accent : Color.white.opacity(0.14),
                            lineWidth: isCurrent ? 1.5 : 0.5)
            )
    }
}

/// 登录页背景：缓慢漂移的热门海报墙 + 暗化/品牌叠层。
private struct AuthPosterBackdrop: View {
    @State private var posters: [String] = []

    var body: some View {
        ZStack {
            fallbackGradient
            if !posters.isEmpty {
                wall
                    .transition(.opacity)
            }
            Color.black.opacity(0.55).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.5), .black],
                           startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [RFX.accent.opacity(0.35), .clear],
                           center: .top, startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
                .blendMode(.screen)
        }
        .animation(.easeOut(duration: 0.6), value: posters.isEmpty)
        .ignoresSafeArea()
        .task { await load() }
    }

    private var fallbackGradient: some View {
        LinearGradient(colors: [Color(hex: 0x2a1206), Color(hex: 0x140a06), .black],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var wall: some View {
        let columns = split(posters, into: 3)
        return HStack(spacing: 10) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, paths in
                PosterColumn(paths: paths, reversed: index % 2 == 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, -16)
        .blur(radius: 2)
        .opacity(0.9)
        .ignoresSafeArea()
    }

    private func split(_ items: [String], into n: Int) -> [[String]] {
        var result = Array(repeating: [String](), count: n)
        for (i, item) in items.enumerated() { result[i % n].append(item) }
        return result
    }

    private func load() async {
        async let movies = try? TMDBService.shared.trending(.movie)
        async let tv = try? TMDBService.shared.trending(.tv)
        let combined = ((await movies) ?? []) + ((await tv) ?? [])
        var seen = Set<String>()
        let unique = combined.compactMap(\.posterPath).filter { seen.insert($0).inserted }
        posters = Array(unique.prefix(15))
    }
}

/// 单列纵向无缝滚动海报（内容复制 3 份保证窗口始终被填满）。
private struct PosterColumn: View {
    let paths: [String]
    let reversed: Bool

    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let itemH = w * 1.5                       // 2:3 海报
            let loop = itemH * CGFloat(max(paths.count, 1))
            VStack(spacing: 0) {
                ForEach(0..<(paths.count * 3), id: \.self) { i in
                    RemoteImage(path: paths[i % paths.count], size: .w342, seed: "auth-\(reversed)-\(i)")
                        .frame(width: w, height: itemH)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(width: w, alignment: .top)
            .offset(y: offset - (reversed ? loop : 0))
            .onAppear {
                offset = reversed ? loop : 0
                withAnimation(.linear(duration: 45).repeatForever(autoreverses: false)) {
                    offset = reversed ? 0 : -loop
                }
            }
        }
    }
}
