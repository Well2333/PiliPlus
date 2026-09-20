# VideoTogether 分支验证记录与待测报告

> 日期：2026-09-20
> 分支：`videotogether`
> Flutter：3.47.4（已应用仓库 `lib/scripts/patch.ps1` 对应的 Android 补丁）

## 已完成验证

- 协议纯逻辑单元测试：WebSocket 地址、官方字段拼写、四时间戳时钟偏移、播放位置投影、
  BV/分 P/番剧媒体标识和 URL 清理；
- 新增代码及全部接入点静态分析：无问题；
- 全仓库静态分析：应用项目补丁后无 error/warning，仍有上游既存的 37 条 info 级提示；
- 默认服务器时间戳接口：`https://vt.panghair.com:5000/timestamp` 返回有效时间戳和版本号；
- 默认服务器双客户端冒烟测试：创建临时房间、第二客户端加入、成员状态回传、文字消息互通均成功；
- 临时测试房间未持久化，停止上报后由 VideoTogether 服务端自动清理。

## 自动构建状态

本地 Android debug 构建已进入 Gradle `assembleDebug`，但依赖下载阶段连接
`plugins.gradle.org` 超时并终止 TLS 握手，未得到 APK。失败发生在 Kotlin Gradle 插件依赖解析，
不是 Dart 编译、Android 资源或本分支代码错误。推送分支后使用仓库原有 GitHub Actions Android
工作流继续验证完整构建。

## 仍需真实设备验证

- “我的”页不同宽度、横竖屏和登录状态下入口是否无溢出并符合预期位置；
- 设置保存、应用重启和设置导入/导出后的读取；
- 两台真实 PiliPlus 客户端之间的播放、暂停、拖动、倍速和缓冲等待；
- 房主切换投稿分 P、番剧剧集后成员自动跳转；
- 前后台切换、断网重连、主动离开房间及视频页销毁后的资源释放；
- 与官方 VideoTogether 浏览器插件交叉加入同一房间。

语音、EasyShare 和 M3U8 媒体中继不在首版范围，不列为本分支阻塞项。
