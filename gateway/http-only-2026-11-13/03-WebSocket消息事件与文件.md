# 03 WebSocket、实时事件与文件流

## IM 实时接入

将 `server-gateway/ws/`、`route/` 及相关 main 装配迁至 `server-im/internal/realtime`（或显式单独 IM 实时接入进程，先用 ADR 解释实际部署收益）。默认复用 IM 的 HTTP 9112，不为了“搬代码”新增无必要的泛业务 BFF。

迁移范围：Hub/client、HTTP Upgrade、心跳、读写队列、消息大小限制、dispatch、在线路由续租、Presence、PushToMember、session kick、EventPoller、contact coalescer、friend consumer。包依赖只向共享认证/协议/业务服务，不反向导入 server-gateway。

服务内 WS 握手使用 02 的 member 验证链，再创建连接；任何客户端 sender/operator 字段由连接身份覆盖。发送/撤回/已读/回应/重发继续使用原 RPC/service 内核，保留 seq/clientMsgId、幂等、ack 状态、离线补拉。

网关只透明代理 `/ws` 的 Upgrade 和后续帧。不得读取或重新序列化 JSON；二进制帧/关闭码/ping/pong 由端点协议处理，代理只转输。请求/响应里的 upgrade/connection 头按标准处理；不要用普通 HTTP 响应超时关闭已升级连接。

## Redis/MQ 所有权

IM 实时节点继续使用当前 Redis 路由/推送总线与成员键隔离；不同节点的接收方也能收到事件。新旧节点过渡时，唯一 node ID、路由租约、断开清理与跨节点投递都须验证。

- friend.changed：沿用已有 outbox、durable queue、broker ACK、失败退避、租约恢复与客户端 eventId 去重；只投递受影响成员，不广播好友关系。
- contact.changed：保持原语义及合并窗口，不扩大原数据可见范围。
- call.event、announcement.publish、session kick：在所属服务生成并经同一可信实时投递出口送达；不再依赖 gateway 内回调。
- 轮询/订阅/worker 随 context 启停；退出先停止新接入，排水，释放订阅和连接；不能复制原 `context.Background()` 永不取消的 goroutine。
- 只操作现有本地 Docker Redis/RabbitMQ/LiveKit；不删卷、不清队列、不替换真实数据为 mock。

## 文件上传下载

`gateway_routes.go` 的 registerFileProxy、injectMemberBizKey、请求大小检查与流式行为逐项拆解。网关只代理文件请求，File 服务验证成员/管理身份并生成可信内部上下文；外部伪造 member/internal-token/header 不生效。

保留 multipart、分片上传/合并、thumb、download、Range/206、Content-Disposition、Content-Length、取消清理、原大小上限与业务文件引用权限。文件内容不经过普通 JSON body 缓冲、hash 断言或 4MiB 限制。录制播放/下载仍通过原会话/文件引用权限检查，不能因代理改造绕开。

## 场景验收

- 正常两账号 WS 建连、发消息/ack/接收、历史、已读、撤回、重连；伪造发送者拒绝/覆盖。
- 不同 IM 接入节点上各连接一端，验证消息/好友/来电/踢线跨节点投递。
- 关闭 RabbitMQ 发起申请仍落库，恢复后通知；只做专用 QA 账号，finally 恢复 broker。
- 语音/视频各验证创建、来电事件、接听/拒绝/取消/挂断、活动补拉、录制列表。若无硬件权限，只认定信令通过，不冒充媒体通过。
- 文件上/下载、分片、断点 Range、无权限拒绝与大文件传输，确认 gateway 不缓冲整个文件。
