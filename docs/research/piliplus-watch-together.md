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
