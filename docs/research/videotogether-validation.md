# VideoTogether 分支验证记录与待测报告

> 验证跨度：2026-09-20 至 2026-09-21
> 分支：`videotogether`
> Flutter：3.47.4（已应用仓库 `lib/scripts/patch.ps1` 对应的 Android 补丁）

## 已完成验证

- 32 项纯逻辑单元测试：WebSocket 地址、官方字段拼写、四时间戳时钟偏移、播放位置投影、
  BV/分 P/番剧媒体标识、URL 清理、本地播放/暂停、拖动、倍速、缓冲与自然进度判定，以及兼容模式
  控制权、0.5 秒默认阈值、暂停态精确校正、成员缓冲等待策略、远端首次播放/暂停后恢复命令，以及
  Player 未创建时的拉流准备、播放地址加载重试、暂停态不拉流、半开连接 watchdog、重连退避、
  后台/PiP 策略以及重连后流恢复；
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

兼容模式、同步时序和缓冲等待修复提交 `d7a9b2eb` 推送后，使用空 tag 且仅启用 Android 的参数触发
GitHub Actions 运行 [`35514979228`](https://github.com/Well2333/PiliPlus/actions/runs/35514979228)：
Android Release 编译在 6 分 24 秒内完成，Release 发布步骤明确跳过，三种 ABI 产物全部上传。下载的
arm64 产物实测 applicationId 为 `com.example.piliplus.dev.ci`，版本为
`2.1.4-d7a9b2ebd+5397`，签名 SHA-256 与上述固定证书指纹一致。

第一轮跟随端播放状态修复提交 `eccb2c24` 推送后，使用相同的 Android-only、空 tag 参数触发
GitHub Actions 运行 [`35516154740`](https://github.com/Well2333/PiliPlus/actions/runs/35516154740)：
Android Release 编译在 7 分 31 秒内完成，Release 发布步骤明确跳过，三种 ABI 产物全部上传。下载的
arm64 产物实测 applicationId 为 `com.example.piliplus.dev.ci`，版本为
`2.1.4-eccb2c247+5399`，签名 SHA-256 与上述固定证书指纹一致；APK SHA-256 为
`76f5a2b9e17a818ef92ca5550627ec2a900e41f0c7405e883ed6433044c5235a`。
随后真机验证证实该提交只覆盖了底层 Player 已创建后的状态同步：关闭自动播放时，适配器要到
`playerInit()` 结束后才绑定，会话无法触发初始拉流，因此不能将该次 CI 成功视为功能问题已经解决。
后续实现改为视频页建立后立即绑定适配器，并由远端播放态触发与点击封面等价的 Player 准备流程。

初始拉流修复提交 `41bf944a` 推送后，使用 Android-only、空 tag 参数触发 GitHub Actions 运行
[`35518108961`](https://github.com/Well2333/PiliPlus/actions/runs/35518108961)：Android Release 编译在
6 分 18 秒内完成，Release 发布步骤明确跳过，三种 ABI 产物全部上传。下载的 arm64 产物实测
applicationId 为 `com.example.piliplus.dev.ci`，版本为 `2.1.4-41bf944ab+5401`，签名 SHA-256 与
上述固定证书指纹一致；APK SHA-256 为
`e8bb0370b90aca66cca2848b43ee8f976bb2aa8d6318a745ba40c1caee0cc1c5`。

前后台、网络波动和小窗恢复修复提交 `f8bbc017` 推送后，使用 Android-only、空 tag 参数触发
GitHub Actions 运行 [`35524180366`](https://github.com/Well2333/PiliPlus/actions/runs/35524180366)：
Android Release 编译在 6 分 59 秒内完成，Release 发布步骤明确跳过，其他平台任务未启用，三种 ABI
产物全部上传。下载的 arm64 产物实测 applicationId 为 `com.example.piliplus.dev.ci`，版本为
`2.1.4-f8bbc017e+5403`，签名 SHA-256 与上述固定证书指纹一致；APK SHA-256 为
`360e9fd1d442f2c272d3e98627e2a4b4e5495a68d84d97d0ff95209a220b2ba8`。

## 2026-09-21 稳定性修复验证

- 用户真机反馈前后台切换、网络波动和小窗可能断连或失去同步，本轮因此不再把 WebSocket ready 状态当作
  连接健康的充分条件。
- 定向静态分析覆盖会话、WebSocket、播放适配器和 Player 生命周期接入点，结果为 0 问题。
- VideoTogether 定向测试共 32 项通过；新增覆盖半开连接 8 秒 watchdog、1/2/4/8/15 秒重连退避、
  普通后台与 PiP 策略、重连后既有播放流重开，以及暂停房间不误拉流。
- 全仓库 34 项测试通过；完整静态分析无 error/warning，仍只有上游既存的 37 条 info。
- 默认服务器实网冒烟验证成功：临时房主创建房间，成员加入后主动断开，使用全新 WebSocket 再次加入并
  取回相同权威房间快照；整个过程客户端错误数为 0，临时房间停止上报后由服务端自动清理。
- 自动化环境无法模拟 Android 进程冻结、系统 PiP 回调顺序和真实 Wi-Fi/蜂窝切换，仍保留以下真机验收项。


## 2026-09-21 多代理竞态复核与加固

- 三个独立审查分别检查会话/连接所有权、播放器/页面生命周期和故障测试覆盖；第二轮再对完整修复差异做
  只读复核。审查确认并修复了旧会话任务串入新房间、重连前写入旧状态、握手关闭后被迟到 ready 复活、
  权限冲突复用旧 WebSocket、播放器异常误拆健康连接、旧媒体请求/seek 落到新视频等竞态。
- 会话和连接均增加代际/所有权校验；重连先加入房间取得权威快照，期间请求合并。控制权冲突会先关闭原
  WebSocket，再用新连接以成员身份加入；播放器恢复失败只降级本轮播放同步，不主动破坏传输连接。
- 跟随端使用带房间修订号的 latest-wins 工作队列；远端命令跨会话串行，每条异步播放器操作前后都校验
  command epoch 并维持本地变化抑制。心跳、watchdog 和退避间隔均改用单调时钟。
- 视频 URL 查询和底层 Player 换源均按代际串行收敛；旧 open 不再触发自动播放/初始化，seek 绑定 Player
  与媒体代际并加入 5 秒缓冲等待、8 秒 duration 等待上限，避免换源后应用旧进度。
- Android 自动 PiP 使用最长 3 秒过渡窗口：真实 PiP 及时确认则持续同步，未确认则按普通后台暂停；确认
  迟到时会自动解除挂起、重连并恢复权威状态。返回视频页改为按当前房间状态决定是否起播。
- VideoTogether 定向测试 42 项通过，其中协议/播放状态机 37 项、WebSocket 所有权与故障注入 5 项；
  全仓库 44 项测试通过。
- 定向静态分析为 0 问题；全仓库静态分析无 error，修复本轮唯一 warning 后仅剩上游既存 37 条 info。
- 默认服务器实网复测成功：临时房间创建、成员加入、成员断开后以全新 WebSocket 再加入均取回同一房间，
  客户端错误数为 0；停止上报后房间由服务端自动清理。
- Fork GitHub Actions 运行 `35532050491` 在提交 `f814255c` 上用时 7 分 05 秒成功完成；仅 Android 三种
  ABI 产物上传，`Release` 与其他平台任务均明确跳过，没有 tag 或 GitHub Release。
- arm64-v8a 产物的二进制清单包名为 `com.example.piliplus.dev.ci`；签名证书 SHA-256 为
  `F0:64:C9:F8:88:E2:BE:3D:F4:0C:AA:35:EB:60:AC:3A:83:8A:51:B7:2E:8B:FE:A5:17:5B:07:33:67:C4:72:54`。
- 自动化仍无法代替 Android 真机的系统 PiP 回调顺序、进程冻结和 Wi-Fi/蜂窝切换，相关项目继续保留在
  下方真实设备验收清单。

## 2026-09-21 入口与客户端识别验证（历史）

> 本节记录提交 `2d9a3ef2` 当时的验证结果。后续已按产品决策撤回客户端识别、昵称后缀、人数统计和
> 自动兼容绕过；该历史构建不代表当前行为。

- 复核官方提交 `3c61f12b` 的成员模型、房间序列化与 `send_txtmsg` 处理，确认官方协议不广播成员身份，
  自动空消息握手会干扰官方插件；实现因此只从真实文字消息被动确认其他 PiliPlus 客户端。
- VideoTogether 定向测试 47 项通过：协议/播放/能力策略 42 项，WebSocket 所有权与故障注入 5 项；新增
  覆盖后缀编码与隐藏、重复默认昵称的唯一会话计数、成员数变化清空、兼容模式自动绕过和入口可见性策略。
- 全仓 49 项测试通过；所有本轮接入点定向静态分析为 0 问题，全仓静态分析无 error/warning，仍只有上游
  既存的 37 条 info。
- 功能提交 `2d9a3ef2` 推送后，以 Android-only、空 tag 参数触发 GitHub Actions 运行
  [`35553126147`](https://github.com/Well2333/PiliPlus/actions/runs/35553126147)：Android Release 编译在
  7 分 02 秒内完成，`Release` 发布步骤以及 iOS、Windows、Linux、macOS 任务均明确跳过，未创建 tag 或
  GitHub Release；三种 Android ABI 产物均上传成功。
- 下载的 arm64-v8a 产物实测 applicationId 为 `com.example.piliplus.dev.ci`、显示名为
  `PiliPlus dev CI`、版本为 `2.1.4-2d9a3ef22+5407`，APK v2 签名有效且证书 SHA-256 与上述固定开发
  证书一致；APK SHA-256 为
  `1033e5c8b64902ff430747ad0adf56120f2a993816969186ea90281b9551b826`，与 GitHub Artifact 摘要一致。
- 操作栏实际布局、房间内开关即时刷新和混合官方客户端行为仍需按下方清单真机验收。

## 2026-09-21 显式双向控制调整验证

- 已移除昵称 `[piliplus]` 后缀、内部会话标识、PiliPlus 用户计数、被动识别集合和自动兼容模式绕过；
  全仓代码搜索确认不再存在对应运行时代码或设置键。
- 双向同步开关从通用设置页移到已加入房间页面，修改后立即持久化；会话的控制权判断只读取该显式选择，
  不再依据聊天消息或推测的客户端类型改变。
- VideoTogether 定向 43 项测试通过，其中协议/播放/入口与恢复策略 38 项、WebSocket 所有权与故障注入
  5 项；全仓 45 项测试通过。
- 本轮修改文件定向静态分析为 0 问题；全仓静态分析无 error/warning，仍只有上游既存 37 条 info。
- 功能提交 `520408eb` 推送后，Android-only、空 tag 的 GitHub Actions 运行
  [`35563150878`](https://github.com/Well2333/PiliPlus/actions/runs/35563150878) 在 5 分 25 秒内成功；
  三种 ABI 均上传，`Release` 发布步骤与 iOS、Windows、Linux、macOS 任务明确跳过，未创建 Release。
- arm64-v8a 产物实测 applicationId 为 `com.example.piliplus.dev.ci`、版本为
  `2.1.4-520408ebe+5409`，APK v2 签名有效且证书 SHA-256 与固定开发证书一致；APK SHA-256 为
  `2b3df72128d270de45deed8ab97719fa34fbca39c98ce55be274980e88fdaeb2`，与 Artifact 摘要一致。
- 房间页开关布局、设置跨重启保留和混合官方客户端的实际控制体验仍需按下方清单真机验收。

## 2026-09-21 视频切换夺控修复验证

- 根因是本地媒体切换只在新播放器绑定后登记，且房间更新发出前就清除了待夺控标记；被其他客户端接管后，
  加载新流期间仍可能应用旧房间状态，写入冲突也会让本次切换意图静默丢失。
- 投稿分 P、番剧剧集和同页视频切换现在会在播放器重置前登记夺控，使旧远端播放器命令失效，并立即使用
  新 `tempUser` 进入待确认控制状态；新媒体绑定后再次发布目标 URL。
- 媒体切换不再等待播放器完成拉流才发布，夺控标记仅在服务端确认房间更新后按媒体切换修订号清除；较早
  请求的响应不能覆盖后续切换。兼容模式下从未持有控制权的普通成员仍保持只读。
- 新增纯逻辑策略测试，覆盖曾持有控制权者在兼容模式下重新接管、开启双向控制的成员接管，以及兼容模式
  普通成员拒绝接管。VideoTogether 定向 44 项和全仓 46 项测试通过；本轮修改文件定向静态分析为 0 问题。
- 修复提交 `e38e6e3d` 推送后触发 Android-only、空 tag 的 GitHub Actions
  [运行 `35614906952`](https://github.com/Well2333/PiliPlus/actions/runs/35614906952)。首次尝试因第三方
  x86_64 libmpv JAR 下载返回 HTTP 504 失败；仅重跑失败任务后于 7 分 11 秒内成功。
- 工作流仅执行 Android，iOS、macOS、Windows、Linux 与 Release 步骤全部跳过；构建命令明确传入
  `--android-project-arg ci=1`，三个 ABI 产物均已上传。
- arm64-v8a、armeabi-v7a、x86_64 Artifact 摘要分别为
  `sha256:0ad4ae3a698b2173d12b757e08557119576a53876654c11b56e6ae668eb92fc4`、
  `sha256:91ef4a7a599d832023b777e9829b08a591ca646f931b4984d180fd258e0a3129` 和
  `sha256:09173954169f6c2e9a08fb266ab7addc2b5d3f83047bf07e6263cadc9b788810`。
- 仍需用两个真实客户端验证“A 控制 → B 抢控 → A 切换分 P/剧集/其他视频”的服务端写权交接和成员跳转。

## 2026-09-21 房间视频打开策略验证

- 原布尔“自动打开房间视频”已扩展为“始终自动进入”、“仅在视频页自动切换”、“从不自动进入”和
  “倒计时弹窗确认”四档；新安装默认使用 5 秒倒计时确认。既有显式布尔值迁移为始终/从不，避免升级后
  反转用户原选择。
- 会话与界面间的导航结果已区分打开、策略暂缓、用户取消和页面不支持。取消同一视频后不反复弹窗；
  “仅在视频页”因页面条件暂缓后仍会重新评估。手动“打开房间视频”始终绕过自动策略。
- 房间切换视频、设置变更、本地媒体接管和离开房间都会废弃导航代际并关闭仍在显示的倒计时；确认前再次
  校验房间目标 URL，过期弹窗不得导航到旧视频。弹窗取消不会被误报为“不支持页面”。
- VideoTogether 定向 49 项测试和全仓 51 项测试通过；新增纯逻辑测试覆盖默认值、四档映射、仅视频页条件、
  手动强制打开，以及旧布尔值和异常持久化值迁移。
- 本轮修改文件定向静态分析为 0 问题；全仓静态分析无 error/warning，只有上游既存的 37 条 info。
- 功能提交 `10ef53f8` 推送后，Android-only、空 tag 的 GitHub Actions
  [运行 `35621623928`](https://github.com/Well2333/PiliPlus/actions/runs/35621623928) 在 6 分 50 秒内
  成功。Android Release APK 编译和三个 ABI 上传完成；Release、Dev APK、iOS、macOS、Windows、Linux
  步骤均明确跳过，未创建 tag 或 GitHub Release。
- arm64-v8a、armeabi-v7a、x86_64 Artifact 摘要分别为
  `sha256:daa5f9bece88a603f5b9da3a42681d7ee3bee8a711132a0b74b276660b684cf2`、
  `sha256:a5a1098c2e1eb8f8e40364078e955b48f219e3d9a4a099e2a2db7dad8ebfb103` 和
  `sha256:a1ff13f296a2f92f0fbdca97f0ccd51208f713cf89b19e24ec6d05aeaccd4f26`。
- arm64 产物的二进制清单包名为 `com.example.piliplus.dev.ci`；签名证书 SHA-256 仍为
  `F0:64:C9:F8:88:E2:BE:3D:F4:0C:AA:35:EB:60:AC:3A:83:8A:51:B7:2E:8B:FE:A5:17:5B:07:33:67:C4:72:54`。
- 自动化环境未执行真实 Android 导航栈和触摸交互，倒计时自动进入、按钮取消、弹窗显示内容以及房间切换
  时的视觉行为仍列入下方真机验收。

## 仍需真实设备验证

- “我的”页不同宽度、横竖屏和登录状态下入口是否无溢出并符合预期位置；
- 设置保存、应用重启和设置导入/导出后的读取；
- 新安装默认显示 5 秒倒计时确认；分别验证“立即进入”、倒计时结束自动进入和“取消”，取消后同一视频
  不重复弹窗，房间切换视频后可以再次提示；
- 倒计时显示期间让房主再次切换视频、成员修改设置或离开房间，确认旧弹窗关闭且不会打开过期视频；
- 四档设置逐一验证：“始终”可从任意页进入，“仅视频页”不打断其他页面但之后进入视频页可重新跟随，
  “从不”只允许房间页手动打开，手动打开在所有档位都立即生效；
- 两台真实 PiliPlus 客户端之间的播放、暂停、拖动、倍速和缓冲等待；
- 房主切换投稿分 P、番剧剧集后成员自动跳转；
- 房主和成员分别在播放/暂停时切后台，短时及超过 8 秒后恢复前台，确认先追赶服务端状态且不因系统暂停抢控；
- 飞行模式断开再恢复、Wi-Fi 与蜂窝网络互切，确认界面经历断开/重连且恢复后重开流、校正进度；
- Android 手动/自动 PiP 中播放、暂停和拖动，确认 Player 不被后台生命周期误暂停且房间仍持续同步；
- 主动离开房间及视频页销毁后的计时器、网络订阅、播放器绑定和 WebSocket 资源释放；
- 与官方 VideoTogether 浏览器插件交叉加入同一房间。
- 在 PiliPlus 未起播和已跟随暂停两种状态下，验证浏览器房主开始/恢复播放时均能立即起播。
- 关闭双向同步后验证：普通成员本地操作立即恢复跟随且不抢控；创建者被接管后自动降级，并能通过新的
  本地操作重新取得控制权；重点覆盖被抢控后切换投稿分 P、番剧剧集或其他视频时立即用新 `tempUser`
  夺回控制并让其他成员跳转。
- 用浏览器事件、服务端广播、PiliPlus 收包和播放器实际起播四个时间戳复测首次播放延迟，区分浏览器
  `readyState`、网络和 Android 播放器启动耗时。
- 人为限制一台成员设备网络，验证卡顿成员继续加载、房主和其他成员临时暂停，并在缓冲恢复后共同继续。
- 投稿/番剧简介操作栏中“一起看”位于分享按钮右侧；默认未入房隐藏，关闭隐藏设置后常显，入房后无论
  设置如何都强制显示，并确认三点菜单不再重复出现入口。
- 房间页面切换双向同步后立即生效且重进应用仍保留；开启时验证 PiliPlus 客户端间可互相接管，关闭时
  验证普通加入者只能跟随，创建者或曾控制端仍可重新接管。
- 与官方浏览器插件或旧客户端混用时关闭双向同步，确认不会因本地播放操作反复抢占控制权。

语音、EasyShare 和 M3U8 媒体中继不在首版范围，不列为本分支阻塞项。
