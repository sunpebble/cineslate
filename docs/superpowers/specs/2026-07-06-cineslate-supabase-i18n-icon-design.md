# Cineslate 去 Supabase + 双语 + 图标 设计

> 2026-07-06 · 移除 Supabase（保留 Plex 播放）、中英双语、App 图标。承接 [2026-07-06-cineslate-rename-design.md](2026-07-06-cineslate-rename-design.md)。

## 决策（已与用户确认）

- **留 Plex 播放**：只删 Supabase 层。Plex/OpenSubtitles/Player 不依赖 Supabase token，保留整条播放线。
- **图标方向**：卵石 + 日出 + 播放三角（负形）。品牌色板：奶油 `#FFF6E8` / 日光黄 `#F7B733` / 卵石灰 `#6E6E73` / 墨色 `#232733`。

## Phase 1：移除 Supabase

无账号、纯本地片单，对齐品牌"private by design 无账号无追踪"。

**删**：`Features/Auth/AuthView.swift`、`Services/AuthStore.swift`。

**`Services/LibraryStore.swift` 重写为纯本地**：
- 去掉 `auth` 依赖、`URLSession`、`restRequest`、token 检查、网络读写、`rollback`、`reset()`、服务端行替换。
- `cacheKey` 固定 `"library"`（不再按 userId 分隔）。
- `loadAll()` = 从 `DiskCache` 载入快照；`add/remove/toggle` 仅乐观更新 + `DiskCache` 持久化。
- `LibraryItem.id` 改计算属性 `"\(tmdbId)-\(mediaType)-\(listType)"`，去 stored `id` 与 CodingKey（本地无需 Postgres 行 id；给 ForEach 稳定身份）。

**`Config/AppConfig.swift`**：删 `supabaseURL`/`supabaseAnonKey`/`supabaseRestURL`/`supabaseAuthURL`/`supabaseFunctionsURL`。留 TMDB + Plex。

**`Services/KeyStore.swift`**：删 `Keychain.supabaseAccount`，`save/load/clear` 去掉默认 account（显式传，调用方只剩 Plex/OpenSubtitles）。

**`App/CineslateApp.swift`**：删 `@StateObject auth`、init 里的 AuthStore、`.environmentObject(auth)`；`LibraryStore()` 无参。

**`App/RootView.swift`**：删登录门（恒进 MainShell）、`onChange(auth.session.userId)`；DEBUG 辅助保留导航 env（`CINESLATE_START_TAB/OPEN_DETAIL/OPEN_SETTINGS/OPEN_BROWSE/SEED_LIBRARY`），删 `FORCE_LOGOUT/AUTOLOGIN` 与 auth 守卫。

**`Features/Settings/SettingsView.swift`**：删 `accountCard`/`signOutButton`/`initials`/`@EnvironmentObject auth`。留 Plex/OpenSubtitles/TMDB/cache 卡片。

## Phase 2：中英双语（xcstrings）

- 新建 `Cineslate/Resources/Localizable.xcstrings`，`developmentLanguage=zh-Hans`（源）+ `en`。
- SwiftUI `Text("…")` 字面量在 String Catalog 存在时自动本地化（编译期抽取）。
- **程序化字符串**显式包 `String(localized:)`：`LibraryList.title`/`apiValue`(显示用)、`MineView.cta(for:)`、各 Service 错误信息、`MediaCards`/`DetailView` 动态文案。
- 抽取范围：发现/我的/详情/浏览/播放/设置 全部 UI 文案。

## Phase 3：图标

SVG（卵石轮廓 + 后方日轮 + 日轮与卵石间播放三角负形）→ `rsvg-convert -w 1024 -h 1024` → `AppIcon.appiconset/icon.png` + `Contents.json` 单一 1024 universal。

## 验证

每阶段末 `xcodegen generate` + `xcodebuild build` + `test`。i18n 期切换模拟器语言验英文化。图标期 build 确认 asset 编译。

## 不做

Harmony 变体（用户明示后续再做）。Supabase 后端项目本身的清理（控制台操作，非代码）。
