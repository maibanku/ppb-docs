# 01 HTTP 所有权、协议适配与透明路由

## 先形成可运行迁移批次

顺序：公共认证组件与服务端权限补齐 → 每个服务自有 HTTP → 管理/认证/Camera 逐域切换 → IM 实时接入 → 最后替换 server-gateway 运行入口。旧服务与旧网关并存期间可双端点灰度，不删除兼容接口；不要先写一个新网关占端口导致现有全部登录失败。

## 服务 HTTP 接入

1. 扩展 `server-pkg/servicehttp`，使路由契约支持 member/manage/camera-subject/anonymous；每类显式策略，默认拒绝。当前 `Contract.Identity` 只允许 member，不能简单改成任意字符串就默认放行。
2. `server-im/api/member-http.json` 的 42 条保持兼容；新增各服务自己的 `api/*-http.json`（或经架构记录选择等价 proto 注解），权威源放服务目录，公共包只承载生成物和无业务的协议工具。
3. 通过 proto 描述符校验 method/RPC/request/response/operator/binding 类型；源与生成物的漂移检查进入 CI。操作者只从该服务认证后的 request context 获取，body/query/path 提供的 operator 不得覆盖它。
4. 当前 IM 采用 HTTP→本机 gRPC 保留拦截器的方式可暂时延续；新增管理适配必须把已验证 actor、IAM 上下文、内部凭据与 request-id 带到 RPC，继续执行逐方法授权。直接 handler 调用只有在抽出等价授权执行链并通过负控后可用。
5. 管理 `auditedRPC/auditedCtxRPC` 与公告成功广播从网关搬回所属业务服务。使用服务已有业务审计事务/事件通道，成功一次写一次；禁止 HTTP 和 gRPC 两层重复记审计，禁止丢弃 IAM 与业务审计原有差异。

## 旧路径与规范前缀

规范前缀建议 IM `/api/v1/im/`，IM 管理 `/api/v1/chat/manage/`，IAM `/iam/` 与认证入口，Camera `/api/v1/camera/`，File `/api/v1/file/`。最终可沿用已发布路径，不为命名美观强迫客户端换地址。

遗留 `/api/v1/user/*` 和 `/api/v1/manage/*` 混合多个服务，必须从服务契约**生成明确的兼容路由配置**，按真实 owner 转发。匹配规则按 exact > 更长 prefix，方法约束明确；配置中的重叠/歧义/缺 owner 启动时拒绝。不要把所有 manage 发给 IAM，也不要把所有 user 发给 IM。

新接口放已有服务前缀即可独立发布；只有新增旧路径别名或新增服务才更新代理配置。网关程序不编译各 RPC 方法；聚合目录工具单独归工具/公共契约模块，不能因文档生成把业务 proto 再链接进 gateway 二进制。

## server-gateway 最终形态

重写 `main.go` 与 HTTP 路由装配，使用标准反向代理或等价稳定组件：

- 固定配置 upstream；禁止请求头/query 指定任意目标（防开放代理）。
- 保留 method、路径、查询、响应状态/业务正文/Content-Type；只按显式兼容规则改路径。
- Authorization/Cookie 正常传给承接服务验证；清除外部伪造的内部 actor、internal-token、IAM assertion 等头。不能再由 gateway 构造业务成员身份。
- TLS、可信代理转发头与 request-id 规则独立配置；保留外部 Host/Origin 的可验证语义，不能令 IAM Cookie/回调/CSRF 同源检查失效。
- 普通请求超时、上传/下载/WS 超时分别配置；不能用普通 JSON 的 4MiB 或 3 秒上限截断文件和长连接。
- 下游错误正文不重解码，不将 int64 转 float64；仅连接失败使用稳定的通用网关错误。
- 不跟随内部 Location 重定向到任意站点；正确处理 IAM 对外 Location、Cookie Path/Secure/SameSite，不能输出内部 9117 地址。
- 热更新可选；若实现必须完整验证新配置后原子替换，失败保留旧配置，不让半份路由生效。

服务增加 `/healthz` 或既有健康口，readiness 验证必须区分进程启动与依赖就绪；不新增业务数据库表来储存代理路由。

## 删除标准

所有原有路由存在服务 HTTP 承接并验证后，再删除网关的 Upstreams、business Registry 闭包、TypedCall 参数绑定、proto 响应裁剪、token mint、manage 权限 resolver/审计包装。兼容目录需要的元数据保留在服务契约工具，不保留死的执行闭包伪装纯网关。

`go list -deps ./server-gateway` 应不出现业务 grpc_gen、grpc、gorm、eventmq、RabbitMQ、IM Hub/route 等运行依赖。不能把它们改名/搬到内部子包后继续让网关 main 调用。
