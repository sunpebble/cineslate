# Cineslate

iOS 26 SwiftUI 影视发现 App，Liquid Glass 设计，集成 TMDB。sunpebble 系列成员，中英双语，仅支持 iOS。

## 技术栈

- **SwiftUI / iOS 26+**，Liquid Glass（`.glassEffect`、`GlassEffectContainer`）
- **TMDB v3** 真实数据（trending / detail / credits / similar / images / search / discover）
- **Plex**（可选）：登录后在详情页播放自己媒体库里的资源，OpenSubtitles 在线字幕
- 纯 `URLSession`，无第三方依赖

## 功能

- **发现**：Hero 轮播、今日热门剧集排行、实时热门电视、按分类 / 工作室浏览、今日热门人物
- **我的**：精选推荐、正在观看 / 即将更新 / 稍后观看 / 观看历史，本地保存
- **详情**：大图 Hero、简介、更多类似、剧照、演职人员，收藏 / 正在观看 / 看过存本地
- **播放**：连接 Plex 账号后，详情页直接播放媒体库片源，支持外挂字幕
- **设置**：TMDB Key 自定义、Plex 连接、OpenSubtitles 字幕、缓存清理

## 隐私

Private by design——无账号、无追踪、无广告。媒体库仅存本机磁盘，不与任何服务器同步。
Plex / OpenSubtitles 为可选外部服务，仅在你主动连接时调用其官方 API。

## 构建

需要 Xcode 26+（含 iOS 26 SDK）和 [xcodegen](https://github.com/yonyz/XcodeGen)。

```bash
xcodegen generate          # 由 project.yml 生成 Cineslate.xcodeproj（已提交，可跳过）
open Cineslate.xcodeproj   # 选 iPhone 模拟器运行
```

## 架构

```
Cineslate/
  App/            入口、路由、根视图、主壳 + Liquid Glass Tab 栏
  Config/         TMDB / Plex 配置
  DesignSystem/   设计 token、Liquid Glass 封装、占位渐变
  Models/         TMDB Codable 模型
  Services/       TMDBService、LibraryStore（本地 DiskCache）、PlexService、OpenSubtitlesService、Keychain
  Features/       Discover / Mine / Detail / Browse / Settings / Player
  Components/     远程图片、媒体卡片、通用组件
  Resources/      Localizable.xcstrings（中英双语）、Assets.xcassets（App 图标）
```

## 本地化

`Localizable.xcstrings` 维护中英双语（`zh-Hans` 源 + `en`）。UI 字符串走 `String(localized:)`，
插值用 `String(format: String(localized:))`；改完 build 即在模拟器按系统语言生效。
