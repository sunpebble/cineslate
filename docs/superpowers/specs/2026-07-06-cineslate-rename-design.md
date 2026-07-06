# Cineslate 改名迁移设计（Reflix → Cineslate）

> 2026-07-06 · 把 `zeroflix/Reflix` 改名并入 sunpebble 系列，定名 **Cineslate**。
> 范围 A：纯标识改名。品牌承诺对齐 / Supabase 项目改名 / App 图标 / 中英双语 / Harmony 变体另开任务。

## 决策

- **新名**：Cineslate（cine 影 + slate 板岩/场记板，一个词、易读易拼、非商标雷区）。
- **标识映射**：

  | 维度 | 旧 | 新 |
  |---|---|---|
  | 仓库/文件夹 | `zeroflix` | `cineslate` |
  | 工程/module/显示名 | `Reflix` | `Cineslate` |
  | `@main` struct | `ReflixApp` | `CineslateApp` |
  | bundle prefix | `com.kunish` | `com.sunpebble` |
  | bundle id | `com.kunish.reflix(.tests)` | `com.sunpebble.cineslate(.tests)` |
  | Keychain service | `com.kunish.reflix` | `com.sunpebble.cineslate` |
  | Keychain keys/accounts | `reflix_*` | `cineslate_*` |
  | 环境变量 | `REFLIX_*` | `CINESLATE_*` |
  | 缓存目录 | `ReflixImages` / `ReflixData` | `CineslateImages` / `CineslateData` |
  | Plex device/product | `Reflix` | `Cineslate` |
  | Plex 回调 scheme | `reflix` | `cineslate` |
  | OpenSubtitles UA | `Reflix v…` | `Cineslate v…` |
  | 登录页字标 | `REFLIX` | `CINESLATE` |

- **机制**：XcodeGen 驱动（已是 xcodegen 工程，`.xcodeproj` 由 `project.yml` 重生成，不手改 pbxproj）。

## 完整改动清单（执行核对用）

### 配置
- `project.yml`：`name`、`bundleIdPrefix: com.sunpebble`、targets `Reflix/ReflixTests`→`Cineslate/CineslateTests`、sources path、Info.plist path、`PRODUCT_BUNDLE_IDENTIFIER`×2、`CFBundleDisplayName`、scheme 名与 build/test targets。
- `.gitignore`：3 处 `Reflix.xcodeproj` → `Cineslate.xcodeproj`。
- `Reflix/Info.plist`：`CFBundleDisplayName`（xcodegen 也会重生成，文件已提交故同步改）。

### 源码（`Reflix/` → `Cineslate/`）
- `App/ReflixApp.swift` → `App/CineslateApp.swift`（`struct ReflixApp`→`CineslateApp`，`@main` 保留）。
- `App/RootView.swift`：8× `REFLIX_*` 环境变量 → `CINESLATE_*`（含文档注释）。
- `Config/AppConfig.swift`：`plexProduct`、`plexCallbackScheme`。
- `DesignSystem/Theme.swift`：注释 `Reflix design tokens` → `Cineslate …`。
- `Features/Auth/AuthView.swift`：`Text("REFLIX")` → `Text("CINESLATE")`。
- `Services/PlexService.swift:279`、`Services/PlexAuth.swift:36`：`X-Plex-Device-Name`。
- `Services/PlexAuth.swift:76`：注释 `reflix://` → `cineslate://`。
- `Services/OpenSubtitlesService.swift:70`：userAgent。
- `Services/KeyStore.swift`：6× key/account + `service`（`com.kunish.reflix`→`com.sunpebble.cineslate`）。
- `Services/Cache/ImageStore.swift`：注释 + 默认参 `ReflixImages`→`CineslateImages`。
- `Services/Cache/DiskCache.swift`：注释 + 默认参 `ReflixData`→`CineslateData`。

### 测试（`ReflixTests/` → `CineslateTests/`）
- 5 文件 `@testable import Reflix` → `Cineslate`。
- `ImageStoreTests.swift`：2× `ReflixImagesTests`→`CineslateImagesTests`。
- `DiskCacheTests.swift`：`ReflixDataTests`→`CineslateDataTests`。

### 目录/文件重命名
- `Reflix/` → `Cineslate/`、`ReflixTests/` → `CineslateTests/`、`Reflix/App/ReflixApp.swift` → `Cineslate/App/CineslateApp.swift`。
- 删 `Reflix.xcodeproj`，`xcodegen generate` → `Cineslate.xcodeproj`。
- 外层文件夹 `zeroflix/` → `cineslate/`。

### README.md
- 标题、设计稿引用、构建命令（`Cineslate.xcodeproj`）、架构树目录名、Supabase 项目段（注明后端项目仍名 `reflix`，待后端迁移任务处理）。

## 不改（明确）

- 历史 specs/plans（`docs/superpowers/{specs,plans}/2026-06-20-*.md`）：当时命名下的工作记录，保留原貌。
- `buildServer.json`：gitignore、stale 路径，编辑器自动重生成。
- App 图标（appiconset 当前为空）、品牌承诺对齐、中英双语、Harmony 变体：另开任务。

## 副作用（pre-release v1.0，可接受）

- bundle id / Keychain service 变更 → 旧装包无法就地升级、Keychain 凭据孤立（无线上用户，忽略）。
- 缓存目录改名 → 本地缓存失效（下次启动重建）。

## 验证

1. `xcodegen generate` 成功生成 `Cineslate.xcodeproj`。
2. `xcodebuild -project Cineslate.xcodeproj -scheme Cineslate -configuration Debug -destination 'generic/platform=iOS Simulator' build` 成功。
3. `xcodebuild … -scheme Cineslate test`（或 build `CineslateTests`）编译通过（验证 `@testable import Cineslate` 解析）。
4. `grep -rni reflix Cineslate CineslateTests project.yml README.md .gitignore` 无残留（预期为空）。
