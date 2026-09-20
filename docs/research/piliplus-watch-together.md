# PiliPlus 多端同步播放调研

> 调研日期：2026-09-20  
> 目标分支：`videotogether`  
> 上游基线：`bggRGjQaUbCoE/PiliPlus@48f07575`

## 目标

为 PiliPlus 增加类似 VideoTogether 的多人同步播放能力，并优先兼容
VideoTogether 的公开服务器协议，使 PiliPlus 客户端能够创建或加入房间、同步视频和播放状态。

## 上游现状

- PiliPlus 的 `main`、`dev`、`dom` 等公开分支未发现多人同步播放实现。
- 项目现有 WebSocket 主要用于直播弹幕；DLNA 属于单客户端向播放设备投放，均不能直接满足房间同步需求。
- 上游仓库目前没有 `AGENTS.md`、`CONTRIBUTING.md` 或现成的 `docs/guidelines/`。

## 公开 fork 调研

对 PiliPlus 的公开 fork 和 GitHub 已索引 Dart 代码检索了以下关键词：

- `一起看`
- `watch_together`
- `watch-together`
- `syncplay`
- `同步播放`

目前能够确认包含实际多人播放同步代码的第三方版本只有
[`Hollow468/PiliPlus`](https://github.com/Hollow468/PiliPlus)。该版本包含：

- 创建与加入数字房间；
- 房主与观众角色；
- 播放、暂停、跳转和定时进度校正；
- 房主转让；
- 自定义后端地址。

其配套服务端为 [`Hollow468/PlayTogether`](https://github.com/Hollow468/PlayTogether)。
本地对服务端执行测试时共 15 项测试通过，说明它是可运行实现，而非仅有界面。

## Hollow468 实现的限制

该实现使用自定义 HTTP/WebSocket 协议，不能直接视为 VideoTogether 兼容实现，并存在以下限制：

- 协议只传递播放状态，没有传递 BV、AV、CID、分 P 或番剧剧集标识；
- 两端必须手动打开同一个视频，切换视频或分集不会同步；
- 聊天与主动请求同步仍是空实现；
- 没有房间密码、账号认证、TLS 或端到端加密；
- 客户端连接后的五分钟断开计时器不会被状态消息刷新；
- 源码中的默认服务地址在调研环境里无法完成 DNS 解析；
- 功能提交位于其最新正式标签之后，未发现包含该功能的正式发布包。
- 同步控制器通过构造参数注入播放器的播放、暂停和跳转回调，这种解耦方式值得参考；但其房间入口位于
  播放器菜单中，接收远端状态时默认底层 Player 已经存在，没有覆盖关闭自动播放后仍停留在封面、
  尚未创建 Player 和拉取媒体流的场景。

因此，本分支不会直接照搬该协议或依赖其后端，只参考其播放器事件接入方式和界面流程。

## 本分支的兼容边界

本分支以 [`VideoTogether/VideoTogether`](https://github.com/VideoTogether/VideoTogether)
的实际客户端/服务端通信为兼容目标，而不是仅实现一个名称相似的私有协议。

对官方浏览器客户端、Go 服务端和 `docs/HttpApiSpec.md` 交叉核对后，确认：

1. 默认服务地址为 `https://vt.panghair.com:5000`；
2. WebSocket 端点为 `/ws?language=zh-cn`，消息使用 JSON；
3. 房主使用 `/room/update` 创建并持续更新房间，成员使用 `/room/join` 和
   `/room/update_member`；
4. 官方客户端每两秒执行同步任务，服务端清理三分钟未更新的房间；
5. 服务端通过 `replay_timestamp` 返回四时间戳，客户端据此修正跨设备时钟差；
6. 房间状态包含 URL、标题、播放/暂停、进度、倍速、时长、成员数和等待缓冲状态；
7. 文字消息使用 `send_txtmsg`；语音、EasyShare 与 M3U8 中继是独立扩展能力。

稳定的协议和架构约定已整理至 `docs/guidelines/videotogether.md`。

## 官方控制权、延迟与缓冲机制复核

2026-09-20 再次获取官方仓库后，`main` 最新提交仍为
[`3c61f12b`](https://github.com/VideoTogether/VideoTogether/commit/3c61f12b84523abed497f690754487b5c21ec6d3)。
复核结论如下：

1. Go 服务端每个房间只保留一个房主 `tempUser`；新身份可以接管，但旧身份继续更新会收到
   `Other Host Is Syncing`。官方浏览器主线不会把被接管的旧房主自动降级为成员；相关恢复改动仍停留在
   未合并的 [PR #177](https://github.com/VideoTogether/VideoTogether/pull/177)。
2. 浏览器房主监听 `play`、`pause`、`seeked` 并立即触发房间更新，另有 2 秒定时心跳；浏览器成员的
   `SyncMemberVideo` 则存在硬编码 1 秒节流。因而“浏览器房主 → PiliPlus 成员”的整秒延迟不是 PiliPlus
   进度阈值造成，浏览器成员的 1 秒节流也不在这条方向上生效。
3. 官方房主在视频 `readyState < 3` 时会暂时把房间发布为暂停，之后依赖后续事件或 2 秒心跳改为播放；
   这可能造成首次播放等待。PiliPlus 接收端没有设计上的 1 秒等待，但旧实现会在一次同步尚未结束时丢弃
   新广播，最迟依靠 400 毫秒轮询补偿。本轮改为合并并立即应用最新广播。真实浏览器和 Android 播放器
   各自启动耗时仍需用真机时间戳联调区分，不能把暂停态 0.1 秒进度校正宣称为首播延迟修复。
4. 当前官方版本仍保留等待成员缓冲：成员上报 `isLoadding`，服务端聚合
   `waitForLoadding`，房主和未卡顿成员暂停，卡顿成员继续加载，状态恢复后再共同播放。它是允许成员
   影响全体的温和反馈通道，但只表达网络/解码卡顿，不传递成员主动播放、暂停或拖动意图。

本分支因此保留默认双向接管，同时增加可关闭的官方兼容模式；等待成员缓冲在两种模式下都可以独立使用。

## 官方断线恢复机制复核

2026-09-21 对官方提交
[3c61f12b](https://github.com/VideoTogether/VideoTogether/commit/3c61f12b84523abed497f690754487b5c21ec6d3)
再次复核后确认：

- 浏览器客户端每 2 秒执行 ScheduledTask，WebSocket 房间快照超过 5 秒未更新即失效；成员随后通过
  HTTP /room/get 拉取权威状态，因此它并不只依赖 WebSocket 的 readyState。
- Go 服务端约每 54 秒发送一次协议层 Ping，60 秒收不到 Pong 才关闭连接。这能清理死连接，但不足以在
  手机切网或短时断网后快速恢复播放同步。
- PiliPlus 的控制端和成员约每 1.8 秒都会收到房间广播或 replay_timestamp，因此本分支以“连续 8 秒
  没有任何服务端消息”判定半开连接，并在网络类型变化、恢复前台时主动重建 WebSocket。
- 重连后先用 /room/join 获取服务端权威快照，再重开播放流并校正状态；原房主最后才尝试恢复写权，
  避免后台自动暂停或旧进度覆盖其他客户端在断线期间产生的新状态。

## 产品入口要求

- 在“我的”页面头像资料区域右上方的快捷按钮组增加“一起看”入口；
- 入口打开创建/加入房间界面；
- 设置页面新增独立的 VideoTogether 子项，用于服务器及相关参数配置；
- 默认复用 VideoTogether 的公开服务器，同时允许用户覆盖服务器地址；
- 同步能力不可影响未启用该功能时的普通播放流程。

## 验证要求

- 协议编解码与时间/进度计算尽量拆成纯逻辑并提供单元测试；
- 运行 Dart/Flutter 格式化和静态检查；
- 至少验证设置读写、房间创建/加入流程和播放器事件接入；
- 无法在自动化环境完成的双设备联调必须记录为待测项，不能以“编译通过”替代可用性结论。
