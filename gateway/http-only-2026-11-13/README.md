# HTTP 透明网关全量改造：Claude Code 执行入口

日期：2026-11-13。状态：需求与交接已编写，待 Claude Code 实施验收。代码根 `/Users/pipi-ban/Desktop/code/vscode/ppb-base`；文档根 `/Users/pipi-ban/Desktop/code/vscode/ppb-docs/gateway/http-only-2026-11-13`。

本次用户最新要求：**全部调整代码，最后网关只做 HTTP 转发；整理完整文档交给 Claude Code，自动压缩上下文，避免过长。** 本目录取代旧 `gateway/README.md` 2026-11-06 方案中“网关保留 gRPC/认证编排/WS 业务处理”的最终目标；旧文档仅作历史依据。

## 最终目标（全部满足才可标记完成）

1. `server-gateway` 是透明反向代理，负责固定配置路由、TLS、连接/流式转发、通用限流、超时、访问日志和健康；不绑定或解码业务请求，不重写业务响应，不签发用户/成员凭据。
2. 网关运行依赖图不含业务 protobuf/gRPC client、GORM/数据库、RabbitMQ、在线成员 Redis 路由、好友/群/通话规则。请求身份与业务权限在所属服务验证。
3. WebSocket 通过 HTTP Upgrade 透明代理到 IM 实时接入；网关不解析 type/payload，不维护成员连接 Hub，不消费业务事件。
4. 所有当前 HTTP 业务入口及特殊入口均有真实承接方，原客户端 URL/JSON 字段/状态码兼容；已有鉴权、撤销、审计、跨应用边界不得削弱。
5. 在某个服务已配置前缀下新增普通 HTTP API，只发布该服务即可生效，不再增加网关 Go 方法。新增旧路径别名可更新/生成路由配置，不写业务闭包。
6. 不以“将旧网关全部搬到一个新 access/BFF，再套一层代理”宣称全量业务归属改造完成。可使用临时兼容桥分批发布，但最终 105 个旧 HTTP→gRPC 适配必须归对应服务；临时桥必须列为未完成。

## 已完成与剩余基线

代码基准 `ppb-base/main@9989a6a`，以现场 git HEAD 再复核。148 条 Registry 业务入口中：42 条 http-proxy；105 条 grpc-proxy（manage 76、user 19、camera 10）；1 条本地系统健康聚合。另有 19 条特殊入口，不能把它们遗漏在 148 条之外。42 条已完成的成员接口必须保留，不能退回旧网关调用。

机器可读清单见 `baseline/routes.csv` 和 `baseline/specials.json`；每个接口都有 operationId、原路径、原 RPC、承接服务和当前状态。文件来自代码快照，不代表新实现已完成。

## 阅读与执行顺序

- [00 基线与逐接口责任](00-基线与责任清单.md)：先建立真实清点与基线。
- [01 HTTP 与契约迁移](01-HTTP接口与路由迁移.md)：所有服务的 API 所有权与网关代理。
- [02 认证权限与登录](02-认证授权与登录编排.md)：必须先通过负控，不能裸删守卫。
- [03 实时通信与文件](03-WebSocket消息事件与文件.md)：WS、MQ、Presence、文件流。
- [04 发布、CI、回退](04-部署配置与发布回退.md)：启动脚本、环境、发布顺序、依赖审计。
- [05 验收标准](acceptance/05-全量验收矩阵.md)：每项测试、证据与结束条件。
- [06 Lead 执行规范](implementation/06-Claude-Lead执行与上下文.md)：持续开发、任务拆分、提交、自动压缩。
- [进度台账](progress/PROGRESS.md)、[压缩检查点](progress/CHECKPOINT.md)、[状态 JSON](progress/STATUS.json)：必须实时更新。

本目录没有测试密码或 token。私有环境沿用本机已有配置，不能把邮箱授权码、JWT、Docker 密码复制到 Git/日志/模型汇报。
