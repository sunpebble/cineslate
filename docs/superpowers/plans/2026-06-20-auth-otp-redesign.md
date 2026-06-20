# 登录页重做 + 邮箱 OTP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把注册/登录页换成「影视海报背景墙 + Liquid Glass 卡片」，并新增邮箱 6 位 OTP 注册登录（OTP 为主，保留密码路径）。

**Architecture:** `AuthStore` 新增两个 GoTrue OTP 方法（`/auth/v1/otp` 发码、`/auth/v1/verify` 验码），复用既有 `decodeToken`/`persist`。`AuthView.swift` 重写为三状态机（`otpEmail`→`otpCode`→密码），新 UI 组件（`OTPCodeField`、`AuthPosterBackdrop`、`PosterColumn`）作为同文件内的 `private struct`，规避脆弱的 pbxproj 手改。

**Tech Stack:** SwiftUI（iOS 26 部署目标）、Liquid Glass、Supabase GoTrue REST、TMDB（海报）。

## Global Constraints

- 部署目标 iOS 26.0：可直接用 `onChange(of:_:)` 两参闭包、`Task.sleep(for:)`、`glassEffect`。
- **无 XCTest target**：每个任务的验证 = `xcodebuild ... build` 输出 `BUILD SUCCEEDED`；UI 任务追加模拟器截图/行为验证。不新建测试框架（YAGNI）。
- 不新增独立 `.swift` 文件、不改 `project.pbxproj`：所有新代码进 `Reflix/Features/Auth/AuthView.swift`（新组件为 `private struct`）与 `Reflix/Services/AuthStore.swift`。
- 密码路径全部保留（`signUp`/`signIn`/`signup` Edge Function/`RootView` DEBUG 自动登录不变）。
- UI 文案中文；颜色/玻璃复用 `RFX` 与 `glassRoundedRect`。
- 邮件模板（Magic Link 加 `{{ .Token }}`）由用户手动在 Dashboard 配置——不在代码任务内，仅影响 OTP 端到端联调。
- 构建命令（统一）：
  ```bash
  xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
  ```
- 提交信息结尾追加：`Claude-Session: https://claude.ai/code/session_01L8AxvqWqit9TfZ1eK9ixEK`

---

## File Structure

| 文件 | 责任 |
|---|---|
| `Reflix/Services/AuthStore.swift` | 新增 `sendEmailOTP` / `verifyEmailOTP` + 私有网络方法，扩展 `localized`。 |
| `Reflix/Features/Auth/AuthView.swift` | 重写 `AuthView`（三状态机）；追加 `OTPCodeField`、`AuthPosterBackdrop`、`PosterColumn` 私有视图。 |

---

## Task 1: AuthStore — 邮箱 OTP 网络方法

**Files:**
- Modify: `Reflix/Services/AuthStore.swift`

**Interfaces:**
- Consumes（已存在）：`run(_:)`、`decodeToken(from:fallbackEmail:)`、`persist(_:)`、`session_`、`AppConfig.supabaseAuthURL`、`AppConfig.supabaseAnonKey`、`AuthError.message`。
- Produces：
  - `func sendEmailOTP(email: String) async -> Bool` —— 成功（HTTP 200）返回 `true`，失败置 `errorMessage` 返回 `false`。
  - `func verifyEmailOTP(email: String, code: String) async` —— 成功建立并持久化 `Session`。

- [ ] **Step 1: 在 `AuthStore` 的「Public actions」区追加两个公开方法**

在 `signOut()` 之后插入：

```swift
    /// 发送 6 位邮箱验证码（注册即登录）。成功返回 true。
    func sendEmailOTP(email: String) async -> Bool {
        var ok = false
        await run {
            try await self.requestEmailOTP(email: email)
            ok = true
        }
        return ok
    }

    /// 校验邮箱验证码并建立 session。
    func verifyEmailOTP(email: String, code: String) async {
        await run {
            let session = try await self.verifyOTPToken(email: email, code: code)
            self.persist(session)
        }
    }
```

- [ ] **Step 2: 在「Networking」区追加两个私有方法**

在 `passwordGrant(...)` 之前（或之后）插入：

```swift
    private func requestEmailOTP(email: String) async throws {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/otp")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "create_user": true,
        ])
        let (data, response) = try await session_.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 200 { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let msg = (json?["msg"] as? String)
            ?? (json?["error_description"] as? String)
            ?? (json?["message"] as? String)
        throw AuthError.message(localized(msg))
    }

    private func verifyOTPToken(email: String, code: String) async throws -> Session {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/verify")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "token": code, "type": "email",
        ])
        return try await decodeToken(from: req, fallbackEmail: email)
    }
```

- [ ] **Step 3: 扩展 `localized(_:)` 覆盖 OTP 错误**

把现有 `localized(_:)` 整体替换为：

```swift
    private func localized(_ message: String?) -> String {
        guard let message else { return "登录失败，请重试" }
        let lower = message.lowercased()
        if lower.contains("invalid login credentials") { return "邮箱或密码错误" }
        if lower.contains("email not confirmed") { return "邮箱尚未验证" }
        if lower.contains("expired") || lower.contains("invalid token") { return "验证码错误或已过期" }
        if lower.contains("for security purposes") || lower.contains("rate limit") || lower.contains("too many") {
            return "操作过于频繁，请稍后再试"
        }
        return message
    }
```

- [ ] **Step 4: 编译验证**

Run:
```bash
xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add Reflix/Services/AuthStore.swift
git commit -m "feat(auth): AuthStore 新增邮箱 OTP 发码/验码方法

Claude-Session: https://claude.ai/code/session_01L8AxvqWqit9TfZ1eK9ixEK"
```

---

## Task 2: OTPCodeField — 6 位验证码输入组件

**Files:**
- Modify: `Reflix/Features/Auth/AuthView.swift`（在文件末尾追加私有视图）

**Interfaces:**
- Consumes：`Color(hex:)`、`RFX.accent`（已存在）。
- Produces：`OTPCodeField(code: Binding<String>, onComplete: (String) -> Void)` —— 满 6 位时回调 `onComplete(digits)`；只接收数字、最多 6 位。

- [ ] **Step 1: 在 `AuthView.swift` 末尾追加 `OTPCodeField`**

```swift

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
```

注：满 6 位可能触发两次 `onComplete`（清洗重置时），消费方（Task 4 `verifyCode`）用 `guard !auth.isWorking` 去重。

- [ ] **Step 2: 编译验证**（未使用的私有视图，Swift 不报错）

Run:
```bash
xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
git add Reflix/Features/Auth/AuthView.swift
git commit -m "feat(auth): 新增 OTPCodeField 6 位验证码输入组件

Claude-Session: https://claude.ai/code/session_01L8AxvqWqit9TfZ1eK9ixEK"
```

---

## Task 3: AuthPosterBackdrop — 海报背景墙

**Files:**
- Modify: `Reflix/Features/Auth/AuthView.swift`（追加 `AuthPosterBackdrop` + `PosterColumn`）

**Interfaces:**
- Consumes：`TMDBService.shared.trending(_:window:)`、`TMDBMedia.posterPath`、`RemoteImage(path:size:seed:)`、`TMDBImageSize.w342`、`RFX.accent`、`Color(hex:)`（均已存在）。
- Produces：`AuthPosterBackdrop()` —— 全屏背景视图，海报未就绪时回退橙色渐变，无空屏。

- [ ] **Step 1: 在 `AuthView.swift` 末尾追加 `AuthPosterBackdrop` 与 `PosterColumn`**

```swift

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
```

- [ ] **Step 2: 编译验证**

Run:
```bash
xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
git add Reflix/Features/Auth/AuthView.swift
git commit -m "feat(auth): 新增 AuthPosterBackdrop 海报背景墙

Claude-Session: https://claude.ai/code/session_01L8AxvqWqit9TfZ1eK9ixEK"
```

---

## Task 4: AuthView 三状态机重写（集成）

**Files:**
- Modify: `Reflix/Features/Auth/AuthView.swift`（替换 `struct AuthView: View { ... }` 整体；保留 Task 2/3 追加的私有视图）

**Interfaces:**
- Consumes：`AuthStore.sendEmailOTP(email:)`、`AuthStore.verifyEmailOTP(email:code:)`、`AuthStore.signUp/signIn`、`AuthStore.isAuthenticated/isWorking/errorMessage`、`OTPCodeField`、`AuthPosterBackdrop`、`glassRoundedRect`、`RFX`、`Color(hex:)`。
- Produces：完整登录页（外部仅由 `RootView` 用 `AuthView()` 挂载，签名不变）。

- [ ] **Step 1: 用以下内容替换文件顶部的 `struct AuthView: View { ... }`（到其闭合大括号为止；不要动下方 Task 2/3 的私有视图）**

```swift
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var step: Step = .otpEmail
    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var resendCooldown = 0
    @FocusState private var focus: Field?

    private enum Step { case otpEmail, otpCode, password }
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            AuthPosterBackdrop()

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

    private var brand: some View {
        VStack(spacing: 12) {
            Text("REFLIX")
                .font(.system(size: 46, weight: .black))
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
            switch step {
            case .otpEmail: otpEmailContent
            case .otpCode:  otpCodeContent
            case .password: passwordContent
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xff6b6b))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassRoundedRect(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Step contents

    @ViewBuilder private var otpEmailContent: some View {
        field(icon: "envelope.fill", placeholder: "邮箱", text: $email, field: .email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.emailAddress)

        primaryButton(title: "发送验证码", enabled: validEmail) { sendCode() }

        switchLink(title: "用密码登录 ›") { switchStep(.password) }
    }

    @ViewBuilder private var otpCodeContent: some View {
        VStack(spacing: 4) {
            Text("验证码已发送至")
                .font(.system(size: 13))
                .foregroundStyle(RFX.text3)
            Text(email)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)

        OTPCodeField(code: $code) { entered in verifyCode(entered) }
            .disabled(auth.isWorking)

        HStack {
            Button(resendTitle) { sendCode() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(resendCooldown > 0 ? RFX.text4 : RFX.accentBright)
                .disabled(resendCooldown > 0 || auth.isWorking)
            Spacer()
            Button("‹ 换个邮箱") { switchStep(.otpEmail) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RFX.text3)
        }

        if auth.isWorking {
            ProgressView().tint(.white).padding(.top, 2)
        }
    }

    @ViewBuilder private var passwordContent: some View {
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

        primaryButton(title: isRegister ? "注册并登录" : "登录",
                      enabled: validEmail && password.count >= 6) { submitPassword() }

        switchLink(title: "用验证码登录 ›") { switchStep(.otpEmail) }
    }

    // MARK: Reusable pieces

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
                if field == .email, step == .password { focus = .password }
                else if field == .email { sendCode() }
                else { submitPassword() }
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

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RFX.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled || auth.isWorking)
        .padding(.top, 4)
    }

    private func switchLink(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RFX.text3)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var resendTitle: String {
        resendCooldown > 0 ? "重新发送 (\(resendCooldown)s)" : "重新发送验证码"
    }

    private var validEmail: Bool { email.contains("@") }

    // MARK: Actions

    private func switchStep(_ target: Step) {
        auth.errorMessage = nil
        if target != .otpCode { code = "" }
        focus = nil
        withAnimation { step = target }
    }

    private func sendCode() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard mail.contains("@") else { return }
        focus = nil
        Task { @MainActor in
            email = mail
            let ok = await auth.sendEmailOTP(email: mail)
            guard ok else { return }
            if step != .otpCode { withAnimation { step = .otpCode } }
            startResendCooldown()
        }
    }

    private func verifyCode(_ entered: String) {
        guard !auth.isWorking else { return }
        Task { @MainActor in
            await auth.verifyEmailOTP(email: email, code: entered)
            if !auth.isAuthenticated { code = "" }   // 失败则清空可重输
        }
    }

    private func submitPassword() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard mail.contains("@"), password.count >= 6 else { return }
        focus = nil
        Task { @MainActor in
            if isRegister {
                await auth.signUp(email: mail, password: password)
            } else {
                await auth.signIn(email: mail, password: password)
            }
        }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Task { @MainActor in
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run:
```bash
xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 模拟器视觉验证（未登录态）**

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; \
APP=$(xcodebuild -project Reflix.xcodeproj -scheme Reflix -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}'); \
xcrun simctl install "iPhone 17 Pro" "$APP"; \
xcrun simctl launch "iPhone 17 Pro" $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist"); \
sleep 4; xcrun simctl io "iPhone 17 Pro" screenshot /tmp/auth_otpemail.png
```
Expected: 截图显示海报背景墙（或橙色回退）+ 玻璃卡片 + 邮箱输入框 + 「发送验证码」+ 「用密码登录 ›」。
查看：用 Read 工具读 `/tmp/auth_otpemail.png` 人工确认布局正确、无重叠/截断。

- [ ] **Step 4: 行为验证（密码路径未被破坏）**

```bash
xcrun simctl launch --terminate-running-process \
  --setenv REFLIX_AUTOLOGIN_EMAIL "you.rate.me@gmail.com" \
  --setenv REFLIX_AUTOLOGIN_PASSWORD "test123456" \
  "iPhone 17 Pro" $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist"); \
sleep 6; xcrun simctl io "iPhone 17 Pro" screenshot /tmp/auth_password_login.png
```
Expected: 截图显示已进入 `MainShell`（Discover 首页），证明密码 `signUp`/`signIn` 路径仍工作。
读 `/tmp/auth_password_login.png` 确认。

- [ ] **Step 5: 提交**

```bash
git add Reflix/Features/Auth/AuthView.swift
git commit -m "feat(auth): AuthView 重写为 OTP/密码三状态机 + 海报背景

Claude-Session: https://claude.ai/code/session_01L8AxvqWqit9TfZ1eK9ixEK"
```

---

## Task 5: OTP 端到端联调（依赖用户已配置邮件模板）

**前置：** 用户已在 Supabase Dashboard → Authentication → Emails → Magic Link 模板正文加入 `{{ .Token }}`。

**Files:** 无代码改动（纯联调；若发现 bug 回到对应任务修复）。

- [ ] **Step 1: 触发发码并人工确认**

在模拟器（或真机）跑到 `otpEmail` 态，输入 `you.rate.me@gmail.com` → 点「发送验证码」。
Expected：进入 `otpCode` 态，60s 冷却倒计时开始，无错误。

- [ ] **Step 2: 输入邮件收到的 6 位码**

请用户从邮箱取回 6 位码并输入；满 6 位自动校验。
Expected：校验通过 → 进入 `MainShell`；失败则显示「验证码错误或已过期」且输入清空。

- [ ] **Step 3: 验证完成**

确认 OTP 注册即登录、session 持久化（杀掉 App 重开仍登录）。无需提交。

---

## Self-Review（已执行）

**1. Spec coverage：**
- UI 重做（海报墙 + 玻璃）→ Task 3 + Task 4。✓
- 邮箱 6 位 OTP（发码/验码）→ Task 1（网络）+ Task 2（输入）+ Task 4（状态机）。✓
- OTP 为主 + 保留密码 → Task 4 三状态机，密码路径 `passwordContent`/`submitPassword` 保留。✓
- 邮件模板 `{{ .Token }}` → 用户手动（spec 决策 A），Task 5 前置说明。✓
- 不改 pbxproj/RootView/Edge Function → Global Constraints + 文件表。✓

**2. Placeholder scan：** 无 TBD/TODO；每个代码步骤均含完整可粘贴代码。✓

**3. Type consistency：**
- `sendEmailOTP(email:) -> Bool` / `verifyEmailOTP(email:code:)`：Task 1 定义，Task 4 `sendCode`/`verifyCode` 调用，签名一致。✓
- `OTPCodeField(code:onComplete:)`：Task 2 定义，Task 4 `OTPCodeField(code: $code) { ... }` 调用一致。✓
- `AuthPosterBackdrop()`：Task 3 定义，Task 4 `body` 调用一致。✓
- `Step`/`Field` 枚举、`switchStep`/`validEmail`/`resendTitle` 等仅在 Task 4 内部使用，自洽。✓

---

## Execution Handoff

实现按 Task 1 → 5 顺序。Task 1–4 为代码任务（编译 + 截图验证），Task 5 为联调（需用户配置模板 + 提供邮件码）。
