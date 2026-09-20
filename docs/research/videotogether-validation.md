# VideoTogether 分支验证记录与待测报告

> 日期：2026-09-20
> 分支：`videotogether`
> Flutter：3.47.4（已应用仓库 `lib/scripts/patch.ps1` 对应的 Android 补丁）

## 已完成验证

- 14 项纯逻辑单元测试：WebSocket 地址、官方字段拼写、四时间戳时钟偏移、播放位置投影、
  BV/分 P/番剧媒体标识、URL 清理，以及本地播放/暂停、拖动、倍速、缓冲与自然进度判定；
- 新增代码及全部接入点静态分析：无问题；
- 全仓库静态分析：应用项目补丁后无 error/warning，仍有上游既存的 37 条 info 级提示；
- 默认服务器时间戳接口：`https://vt.panghair.com:5000/timestamp` 返回有效时间戳和版本号；
- 默认服务器双客户端冒烟测试：创建临时房间、第二客户端加入、成员状态回传、文字消息互通均成功；
- 默认服务器 A→B→A 写权交接冒烟测试：B 使用新 `tempUser` 接管后 A 的旧身份被拒绝，
  A 重连为跟随端后可再用新身份接管，B 的旧身份随后被拒绝；
- 临时测试房间未持久化，停止上报后由 VideoTogether 服务端自动清理。
- fork 固定 Android 开发证书已写入四项 GitHub Actions Secrets；SHA-256 指纹为
  `F0:64:C9:F8:88:E2:BE:3D:F4:0C:AA:35:EB:60:AC:3A:83:8A:51:B7:2E:8B:FE:A5:17:5B:07:33:67:C4:72:54`。

## Android 构建状态

本地 Android debug 构建已进入 Gradle `assembleDebug`，但依赖下载阶段连接
`plugins.gradle.org` 超时并终止 TLS 握手，未得到 APK。失败发生在 Kotlin Gradle 插件依赖解析，
不是 Dart 编译、Android 资源或本分支代码错误。
本次修复后的 `.dev.ci` Release 实编译同样在 Kotlin/Android Gradle 插件下载时遇到
`plugins.gradle.org` 和 Google Maven TLS 握手中断，尚未在本机产出可核对包名与签名的新 APK。

推送分支后，仓库原有 GitHub Actions Android 工作流在运行
[`35504532718`](https://github.com/Well2333/PiliPlus/actions/runs/35504532718) 中完成 Release 构建并通过，
成功上传 `armeabi-v7a`、`arm64-v8a` 和 `x86_64` 三种 ABI 的 APK。

本次修复和分发调整推送后，GitHub Actions 运行
[`35510008649`](https://github.com/Well2333/PiliPlus/actions/runs/35510008649) 在 6 分 28 秒内完成，固定签名写入、
Release 编译和三种 ABI 上传全部成功。下载的 arm64 产物实测 applicationId 为
`com.example.piliplus.dev.ci`，版本为 `2.1.4-3f8d9d42a+5395`，签名 SHA-256 与上述固定证书指纹一致。

## 仍需真实设备验证

- “我的”页不同宽度、横竖屏和登录状态下入口是否无溢出并符合预期位置；
- 设置保存、应用重启和设置导入/导出后的读取；
- 两台真实 PiliPlus 客户端之间的播放、暂停、拖动、倍速和缓冲等待；
- 房主切换投稿分 P、番剧剧集后成员自动跳转；
- 前后台切换、断网重连、主动离开房间及视频页销毁后的资源释放；
- 与官方 VideoTogether 浏览器插件交叉加入同一房间。
- 播放器菜单首项和“隐藏播放器菜单入口”开关在真机上的显示、持久化和导航。

语音、EasyShare 和 M3U8 媒体中继不在首版范围，不列为本分支阻塞项。
