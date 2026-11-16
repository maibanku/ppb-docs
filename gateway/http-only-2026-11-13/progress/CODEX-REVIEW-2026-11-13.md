# HTTP-only 网关改造独立复核

日期：2026-11-13。复核代码：ppb-base `0f46462`。本轮只读审查和隔离复现，未修改业务代码、未替换 Claude 的验收状态。

## 结论

**网关运行时职责拆分基本完成，但不通过完整验收，不能把 STATUS.json 的 complete 视为功能全部可用。**

网关依赖图未发现业务 gRPC、ORM、Redis、MQ 等禁项；业务 HTTP 鉴权与 WS 接入已迁入所属服务。现有测试共 61 个包通过（部分使用 Go 缓存）。独立补充场景发现下列问题；正常测试全绿并未覆盖这些组合路径。

## 必须修复的问题

### R1 / P1：代理修改 Host，IAM 同源请求被误判跨站

位置：`ppb-base/server-gateway/transparent.go:94-95`；`server-iam/internal/bridge/bridge.go:113`、`:253-269`。

`ProxyRequest.SetURL` 把上游 Host 改成内部地址，而浏览器 Origin 仍是外部地址。IAM 业务桥要求 Origin.Host 等于请求 Host，因此经过网关的合法同源请求被 403 拒绝；校验发生在 Cookie 认证之前，登录 Cookie 无法修复。

此前服务在线时对同一只读路径 `/iam/api/v1/business/manage/members` 的对照：直连 IAM、显式使用相互匹配的外部 Host/Origin 返回 401 IAM-2001（未带 Cookie，预期）；经网关使用相同外部 Host/Origin 返回 403 MANAGE-0004，日志原因是“跨站请求被拒绝”；无 Origin 时返回 401。再次复测时 8080/9117 已拒绝连接，不能将此前观测表述为当前在线状态。

修改：明确可信代理边界后保留外部 Host，或使用经过清理与验证的转发来源信息完成同源校验。禁止通过删除 CSRF 校验解决。验收需包含浏览器 Cookie + Origin 的真实读写、跨站拒绝、伪造转发头负控。

### R2 / P1：Redis 降级条件永远选 Redis，空配置导致启动 panic

位置：`server-im/cmd/server/main.go:128-145,245-251`。

上段在 Redis 缺失或不可用时把 pub 设为非空 DegradedPublisher；下段用 `pub != nil` 判断 Redis 可用，条件恒真。未配置 Redis 时把 nil client 传给实时 Redis 总线，Hub 订阅触发空指针。配置了不可用 Redis 时也不会进入声称的 memory 分支。

复现：直接组合现有 DegradedPublisher、RedisPushBus 和 Hub，捕获 `runtime error: invalid memory address or nil pointer dereference`。临时探针已删除。

修改：共享一次明确的 Redis 就绪结果，统一构造业务路由与实时路由；选择支持的降级策略，或明确拒绝启动，不能打印降级成功却继续使用坏连接。验收覆盖未配置、连接失败、正常 Redis 三种情况。

### R3 / P1：多节点全员广播只覆盖消费节点本地用户

位置：`server-im/cmd/server/main.go:272-295`；`server-im/internal/realtime/ws/ws_hub.go:174-181`。

所有 IM 副本共享 contact/announcement 的同名 RabbitMQ work queue，一条事件只有一个副本消费；BroadcastAll 仅遍历该副本的 MemberKeys。Redis 定向总线不能补出其他副本独有的成员，因此其他节点的用户收不到本次 contact.sync / announcement.publish。点对点 msg.push 测试通过不能证明全员广播通过。

复现：两个 Hub 共用路由表/总线、各连接一个不同成员，节点 A BroadcastAll 后 A 收到，B 未收到。该复现使用隔离测试连接，不是运行环境的 mock 数据；未运行真实双节点 RabbitMQ 故障实验。此问题可能是迁移携带的原有缺陷，不能因此将跨节点能力记为完整验收通过。

修改：采用所有节点订阅的集群广播通道，或节点独立队列，保证每个本地 Hub 收到一次；配合事件去重、退出清理。验收需双节点真实 MQ，覆盖公告和通讯录全量通知。

### R4 / P1：CI 全新环境缺少三个代码生成插件

位置：`.github/workflows/gateway-governance.yml:45-50`；`buf.gen.yaml`。

工作流只安装 Go 和 buf，未安装 buf.gen.yaml 声明的本地 protoc-gen-go、protoc-gen-go-grpc、protoc-gen-grpc-gateway。开发机已有工具掩盖了问题。

复现：清理 PATH 中本地工具路径后执行同一 buf generate，退出 1，三个插件均报 executable file not found。

修改：按仓库约束版本安装三种插件，或切换锁定版本的远端插件；在干净 runner 跑完整生成及 drift 检查。

### R5 / P1：CI lint 比较格式不同，现有基线也被判为新增

位置：`.github/workflows/gateway-governance.yml:79-92`；`idl/buf-lint-baseline.txt`。

当前诊断是 filename:line:column:message，基线是 filename:message。两者仅 split 第一个冒号，前者保留行列号，后者没有。实际 1412 条当前诊断产生 1409 个不匹配 key，导致未增加违规也失败。`|| true` 还应区分正常 lint 违规和工具/配置执行失败。

修改：复用同一规范化器生成和比较基线，保留文件身份、去掉行列噪声、按次数比较；处理执行错误。验收包含当前基线通过、增加一条违规失败、工具错误失败。

### R6 / P2：管理端健康接口被删除，客户端仍调用

位置：`ppb-chat/chat-manage-web/src/api/ops/health.ts:12-13`；`ppb-base/deploy/config/gateway-routes.yaml`。

旧 GET /api/v1/manage/system/health 未迁入当前路由，管理端仍请求 /manage/system/health。Claude 报告把此接口计作退役，原要求是移走网关业务职责，不是删除仍被 UI 使用的功能。源码契约对比确认缺失；最新复测因服务未运行，未获得新的 HTTP 响应。

修改：由 IAM/运维服务承载健康聚合，恢复原返回结构与 system.read 权限，网关只转发；同步真实管理端验证。不能仅修改验收统计把功能下线算通过。

### R7 / P2：启动脚本仍向网关继承业务密钥

位置：`deploy/scripts/start-all.sh` 的全局 export 与 `:368-369` 网关启动。

此前按进程环境变量名称检查，网关仍持有 IM_DB_DSN、IAM_DB_DSN、FILE_DB_DSN、PPB_INTERNAL_RPC_TOKEN、IM_RTC_API_SECRET。这里只记录名称，不包含值。运行时代码虽不使用这些能力，进程权限边界未清理完成。

修改：按服务构造最小环境，网关不继承业务 DSN、内部 RPC 和 RTC 密钥；清理失效配置/注释，区分 go.mod 声明依赖与真实二进制依赖。验收只检查变量名称与依赖图，禁止打印密钥。

## 仍未完成的产品验收

Claude 自述的未验证项仍保留：真实麦克风/摄像头媒体、桌面 E2E；大文件上传受到 MinIO EDEADLK 阻塞；已建 WS 会话在 IAM 撤销后未主动断连；Camera 仍为 SQLite。区分既有缺口与本次回归，但这些项目不能声称已经可用。

建议顺序：R1 浏览器链路 → R2 启动/降级 → R3 多节点通知 → R4/R5 CI → R6 管理端功能 → R7 环境边界，再补真实客户端消息、文件、语音视频回归。完成后再更新原验收报告，保留失败证据与复验日期。

## 证据及变更范围

证据目录：`/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/codex-gateway-review-20261113/`。

- tests.private.log：61 个测试包通过，部分缓存。
- redis-probe.go.txt / redis-probe.log：Redis 组合探针与 panic。
- broadcast-probe.go.txt / broadcast-probe.log：双 Hub 广播漏送的失败测试。
- clean-ci-generate.log：缺少插件失败。
- buf-lint-current.txt / reproductions.log：lint 格式比较结果。
- browser-origin-probe.json：最新端口连接被拒绝的复测结果，不是此前 401/403 的原始日志。

临时源文件已清理，未改业务实现；原有未跟踪 work/claude-control/gateway-p2/ 和文档 RUNTIME-CHECKPOINT.md 的既有修改保持原样。本报告未提交或推送。
