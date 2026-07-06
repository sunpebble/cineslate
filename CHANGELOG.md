# Changelog

## [0.2.2](https://github.com/sunpebble/cineslate/compare/v0.2.1...v0.2.2) (2026-07-06)


### Bug Fixes

* **ios:** hero 海报自适应 iPad 多海报并消除两端空洞 ([59d3a0f](https://github.com/sunpebble/cineslate/commit/59d3a0fdd0220e35ae78008689eb8f2a0129ff8e))

## [0.2.1](https://github.com/sunpebble/cineslate/compare/v0.2.0...v0.2.1) (2026-07-06)


### Bug Fixes

* **ios:** 补 iPad 四方向，解 ITMS-90474 退回 ([ae5d401](https://github.com/sunpebble/cineslate/commit/ae5d40145b16838e8adfb7d3f50ace14e5113a7e))

## [0.2.0](https://github.com/sunpebble/cineslate/compare/v0.1.0...v0.2.0) (2026-07-06)


### Features

* **auth:** AuthStore 新增邮箱 OTP 发码/验码方法 ([06900cd](https://github.com/sunpebble/cineslate/commit/06900cd246f13998bafcde71f5baa88814847eda))
* **auth:** AuthView 重写为 OTP/密码三状态机 + 海报背景墙 ([7ffaaa9](https://github.com/sunpebble/cineslate/commit/7ffaaa97c45b627eef0c4d516ce94513a918d41f))
* **auth:** 新增 AuthPosterBackdrop 海报背景墙 ([b92c8ce](https://github.com/sunpebble/cineslate/commit/b92c8ce5e262e10eb5a33e165a5b6eed8616daa9))
* **auth:** 新增 OTPCodeField 6 位验证码输入组件 ([e3104fb](https://github.com/sunpebble/cineslate/commit/e3104fb72b27777d391a3444a748cd2728c420c6))
* **discover:** 发现页分类卡铺 TMDB backdrop、工作室卡展示网络 logo ([49228a7](https://github.com/sunpebble/cineslate/commit/49228a7e212da49b8560a902cd1dd32bd0ef048f))
* **paywall:** 移除升级到 Pro 横幅，所有功能无 paywall ([927c9be](https://github.com/sunpebble/cineslate/commit/927c9bea5a33e5a0a48cc65193126d3c7119abe8))
* Plex App 内播放 + OpenSubtitles 字幕 ([b161234](https://github.com/sunpebble/cineslate/commit/b161234644bfcb3c8a177e436c70a597067c46b4))
* Plex 媒体源集成 + 状态栏/导航/登录持久化修复 ([59eb4bf](https://github.com/sunpebble/cineslate/commit/59eb4bfb291a4be32d60c5c69df5786403a38cf2))
* Reflix — iOS 26 SwiftUI Liquid Glass 影视 App ([4796ec1](https://github.com/sunpebble/cineslate/commit/4796ec1e12767335477b1a5e5f7bf4ae4626dcd9))
* Reflix → Cineslate 改名并入 sunpebble，去 Supabase + 中英双语 + 图标 ([4b6d8a2](https://github.com/sunpebble/cineslate/commit/4b6d8a2d5d9f9a9dfed9e3fd970ca7a1e2aa55d2))
* 本地优先数据与图片缓存 ([271814a](https://github.com/sunpebble/cineslate/commit/271814a2a90bf148cfe5491d11ca60e9e0f032dc))


### Bug Fixes

* **plex:** 修复 Plex 授权登录后卡在"正在连接…" ([3b36708](https://github.com/sunpebble/cineslate/commit/3b367082e6f26abaa4984eeeff754d284f3bb077))
* 修复缓存审查发现的并发/正确性问题 ([f179a94](https://github.com/sunpebble/cineslate/commit/f179a94d7fbb7ba329c3d785e8ebbd21bbdf518b))
* 全幅图布局/命中测试 + 详情动作 chips + 我的分段标签 ([195168b](https://github.com/sunpebble/cineslate/commit/195168b4b0577912c3a0d9689e716b075e4b3ddd))
