# VideoTogether 兼容实现约定

本文档约束 PiliPlus 的 VideoTogether 兼容功能。修改协议、播放器接入或房间生命周期时，
必须同步更新本文档和对应测试。

## 兼容目标

- 以 `VideoTogether/VideoTogether` 官方 Go 服务端和浏览器客户端的当前协议为准。
- 默认服务地址为 `https://vt.panghair.com:5000`，用户可以在设置中覆盖。
- 服务地址只允许 `http` 或 `https`；WebSocket 分别映射为 `ws` 或 `wss`，路径为
  `/ws?language=zh-cn`。
- 首版兼容范围包括创建/加入房间、房主状态上报、成员状态上报、视频地址跳转、
  播放/暂停/进度/倍速同步和文字消息。
- 语音通话、EasyShare、M3U8 内容中继和真实媒体地址代理不属于首版范围；未知消息必须忽略，
  不能导致会话断开。

## 协议约定

WebSocket 消息均为以下 JSON 外层结构：

```json
{
  "method": "/room/join",
  "data": {}
}
```

必须支持的客户端请求：

- `/room/update`：房主创建或更新房间；
- `/room/join`：成员加入房间；
- `/room/update_member`：成员上报加载状态和当前页面；
- `send_txtmsg`：发送文字消息。

必须处理的服务端消息：

- `/room/update`、`/room/join`、`/room/update_member`：更新本地房间快照；
- `replay_timestamp`：校正本地与服务端的时钟差；
- `send_txtmsg`：接收文字消息；
- 带 `errorMessage` 的消息：展示错误，但仅在创建/加入失败时结束启动流程。

房主和成员每 2 秒执行一次同步任务。房主上报播放器状态以保持房间存活；成员上报加载状态，
并应用最新房间状态。服务端正式配置会清理三分钟未更新的房间，因此不能只在用户操作时上报。

服务端时钟偏移采用与官方客户端等价的四时间戳计算：

```text
offset = ((serverReceive - localSend) + (serverSend - localReceive)) / 2
```

播放中的目标进度为：

```text
room.currentTime + (serverNow - room.lastUpdateClientTime) * room.playbackRate
```

暂停时直接使用 `room.currentTime`。

## 分层与依赖

- 协议模型和 URL/时间计算必须是可单元测试的纯 Dart 逻辑。
- WebSocket 客户端只负责传输和消息解析，不依赖 Flutter 页面或具体播放器。
- 会话服务只依赖抽象播放接口；`PlPlayerController` 通过单独适配器接入。
- 页面导航以回调注入会话服务，服务层不得直接依赖 PiliPlus 路由实现。
- 普通播放流程不依赖房间服务；未加入房间时，同步逻辑必须无副作用。

## 视频标识与跳转

- 投稿视频使用 `https://www.bilibili.com/video/<bvid>?p=<part>`；第一 P 可以省略 `p=1`。
- PGC 视频优先使用 `https://www.bilibili.com/bangumi/play/ep<epId>`。
- 判断是否为同一视频时比较 BV 号和分 P，或比较 epId；忽略来源跟踪参数和
  `VideoTogether*` 状态参数。
- 成员加入房间后可以按设置自动打开房主 URL。PiliPlus 无法处理的非 B 站页面只提示用户，
  不交给内置 WebView 冒充原生播放器同步。

## 设置与敏感数据

- 服务器地址、显示名称、自动跳转、倍速同步、等待成员缓冲、密码保护和进度校正阈值
  存入现有 `setting` Hive box，并随现有设置导出/导入。
- 房间密码只保存在当前内存会话中，不写入持久化存储或日志。
- 切换服务器地址只影响下一次加入/创建；活动会话不会静默迁移服务器。

## 生命周期

- 房间会话独立于房间页面存在，跳转到视频页后继续同步。
- 播放器未就绪时允许先创建或加入房间；绑定播放器后立即应用当前房间状态。
- 离开房间、创建/加入失败或应用退出时必须停止计时器并关闭 WebSocket。
- 断线后由会话定时任务有限重连；不得同时创建多个 WebSocket 或并发应用多个远端状态。

## 验证

- 对消息编码、房间解析、WebSocket URI、服务器时钟偏移、目标进度和 B 站媒体标识比较
  编写纯逻辑单元测试。
- 每次修改后执行 Dart 格式化、相关单元测试和静态分析。
- 双客户端真实联调至少覆盖：创建/加入、自动打开同一视频、播放/暂停、拖动、倍速、
  切换分 P/剧集、断线重连和离开房间；无法自动完成的项目写入待测报告。
