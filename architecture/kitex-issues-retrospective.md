# Kitex 迁移开发问题复盘与解决方案清单

> 日期：2026-11-23 · 范围：Kitex 迁移全程（P1 camera 试点 → P2-P4 三服务并行 → 替换检查收尾）
> 配套文档：`kitex-migration-plan.md`（方案）、`kitex-execution-steps.md`（执行实录）、
> `kitex-replacement-checklist.md`（替换检查手册）
> 用途：已解决项沉淀为组织知识（含预防措施）；未解决项给出方案与优先级，作为后续批次派工依据。

---

## 一、已解决踩坑实录

### A. 框架与类型系统（Kitex 内部行为，最有复用价值）

| # | 问题 | 根因 | 解决 | 预防 |
|---|---|---|---|---|
| A1 | prutal 类型与 proto.Message 不兼容，servicehttp（protojson 绑定）看似无法与 Kitex 共存——迁移最初的"类型系统级阻塞" | Kitex v0.16 生成 prutal 自有类型，无 ProtoReflect | 深读源码发现服务端默认 **detection 协议探测**：同口承载标准 gRPC 线缆，HTTP 面回环保持 grpc-go 客户端零改动；prutal 为反射式 protobuf 序列化，对 protoc-gen-go 结构体按 tag 直读（**字节一致实测**） | 结论已写入 execution-steps 执行实录：迁移可不重写 HTTP 面 |
| A2 | Kitex 会把 handler 返回的裸错误包成 ErrBiz，nphttp2 convertStatus 追加 `" [biz error]"` 后缀，破坏 `"IAM-xxxx: 文案"` 线缆契约（iam 按码解析的调用方实测红了） | bizHandleEndpoint 包壳 + getStatusForBizErr 拼后缀 | iam 落地 `HandlerStatusFidelityMiddleware`（最内层剥壳还原裸 nphttp2 status error） | handler 直接返回 status 错误的服务都要这件；im 全信封口径天然免疫（逐方法审计确认） |
| A3 | grpc-go 的 `status.Error` 在 Kitex 侧降级 Internal | convertStatus 的 GRPCStatus() 断言类型不匹配（两套 status 包） | transport 层错误统一改 `nphttp2/status.Err(c, msg)`（注意：`status.Error` 在 nphttp2 包里是**类型不是构造函数**，编译期即暴露） | 迁移清单固化：错误出口只用 nphttp2 族 |
| A4 | `authzport.ActorFromContext` 读 grpc-go 入站 metadata，nphttp2 面不可见 → legacy actor 通道断裂 | 两套 metadata 包的 ctx key 不同族 | iam 断言中间件恰单值时同值桥入 grpc-go 入站 metadata | 凡有「读入站 metadata 的存量库函数」都要检查这一断层 |
| A5 | 多服务注册同名方法冲突（ChatOrg 与 OrgCompat 都有 AcceptInvitation）注册期报错 | Kitex 多服务注册要求指定回退服务 | WithFallbackService（挂在 ChatOrg 注册处）；核实 nphttp2 按 :path 严格路由，线缆行为不变 | 多服务同 server 时留意方法重名 |
| A6 | im 业务层 34 文件直消费 contracts proto 类型，camera 式「直接换 prutal 类型」会引发类型级联改写 | prutal 类型与业务层类型不同源 | im 落地 **kitex_gen 别名层**（`type X = contracts.X`），服务组/handler/回环客户端共享同一 Go 类型，方法体逐字不动 | 大型服务的迁移模式分叉：小服务直换 prutal，大服务别名层 |

### B. 依赖与网络环境

| # | 问题 | 根因 | 解决 | 预防 |
|---|---|---|---|---|
| B1 | `go mod tidy` 报 genproto ambiguous import（errdetails 双模块） | 旧整包 genproto 与拆分后 genproto/rpc 并存 | `go get google.golang.org/genproto@latest` 收敛 | 统一 go 工具链环境变量集（见检查手册前置） |
| B2 | proxy.golang.org 超时 | 网络环境 | `GOPROXY=https://goproxy.cn,direct` | 同上，已固化进手册 |
| B3 | 私有 tag 拉取 `unknown revision` | goproxy.cn 无私有仓缓存 | `GOPRIVATE=github.com/maibanku/*`（直连 git）+ **先推 tag 再 bump require** | 发 tag 的顺序纪律 |
| B4 | zsh 不分词：`env $COMMON cmd` 把多个 VAR=VALUE 并成一个畸形赋值（`PPB_ALLOW_DEV_JWT="1 PPB_..."≠"1"`，表象为 D4 闸门误拒） | zsh 默认不做词切分 | env 变量逐个显式写 | 脚本化启动（见遗留 F）可根治此类手误 |

### C. 测试装配

| # | 问题 | 根因 | 解决 | 预防 |
|---|---|---|---|---|
| C1 | bufconn 测试装配全线不可用：gonet 传输 × nphttp2 处理器 nil-deref（serveConn 循环 refreshReadDeadline 取不到 RPCInfo）+ detection 的 ProtocolMatch 依赖 netpoll.Reader（内存连接无法命中 gRPC 前缀探测） | Kitex 测试传输组合与 gRPC 生态的既有差异 | 测试装配改**真实 127.0.0.1:0 回环 TCP + 默认传输**（与生产同构，保真度反而更高）；四服务的 kitex_testserver_test.go 已固化该模式 | 新服务接入直接抄该装配；bufconn 禁令写入手册 |
| C2 | `RegisterService(svr, nil)` panic（camera 单服务用例） | Kitex 注册期 nil 检查直接 panic | 测试 helper 对 nil handler 跳过注册 | — |
| C3 | `pb.XxxService_ServiceDesc.Methods` 枚举在 kitex_gen 不存在 | 无 ServiceDesc 生成物 | 改 `NewServiceInfo().Methods` 映射键枚举（同源 proto） | — |
| C4 | smoke 客户端 Unauthenticated（code=16） | im 服务端 InternalAuth fail-closed，smoke 客户端没带内部凭据 | 客户端补 `internalauth.UnaryClientInterceptor()`——内部调用方应带凭据是正确语义，工具原本就缺 | 冒烟工具纳入「内部调用方」口径 |

### D. 运维与流程

| # | 问题 | 根因 | 解决 | 预防 |
|---|---|---|---|---|
| D1 | HTTP 面回环 503（camera 首次冒烟） | 没设 `PPB_INTERNAL_RPC_TOKEN`——internalauth **客户端**拦截器本地 fail-closed，不走网络 | 补 env；写入手册运行时前置 | 启动脚本化（遗留 F） |
| D2 | camera 管理面差分测试失真：停 IAM 后 403 不变 503 | guard 对上游故障同样 fail-closed 拒绝（安全语义正确，但观测不区分） | 改用 **lsof 连接层证据**（ESTABLISHED = grpc 惰性建连真实发生过） | 跨服务验证方法论：业务码 + 连接层双证据 |
| D3 | contracts-camera 误提交 11 个 kitex 脚手架文件；清理时又漏删引用 kitex_gen 的 main.go 导致模块 tidy/构建挂 | 生成器脚手架误入 contracts 仓 + 清理不彻底 | 两笔清理提交（2f728a4/8b31753） | **CI 门禁：contracts 仓禁止出现 kitex/grpc server 装配物**（遗留 E 落地） |
| D4 | SQLite dev 库文件误入 camera 提交 | data/ 未 ignore | git rm --cached + .gitignore | 各仓补 data/ 忽略规则 |
| D5 | iam deploy yaml 严格解析拒起（oidc/log 未知字段） | deploy 配置 schema 超前于服务 config | 临时用服务自身 config.yaml 做基底 | 系统性问题，见遗留 B |
| D6 | 旧进程占口（9106/9107）导致新二进制起不来 | 跨会话遗留进程 | 逐个定位杀掉 | 启动前端口探测应进启动脚本 |
| D7 | im 代理报告失真一例（称 iam/file 仍是 stubs-only，实为并行推进中的早期快照） | 子代理读仓库时其他代理尚未推送 | 主会话按提交哈希核验纠正 | **并行代理的报告以 git 哈希为准核验**，不直接采信叙述 |

---

## 二、遗留问题与解决方案（按优先级）

### P0（影响正确性/会再咬人）

1. **deploy 配置 schema 漂移（D5 系统化）**
   - 现状：`ppb-base/deploy/config/*.yaml` 与各服务 `LoadConfig` 严格 schema 不同步（iam 的 oidc/log 字段服务不认；camera 的 jwt 分层 vs 服务扁平键）。deploy yaml 目前**不能直接喂给服务起服**，只是"文档态"。
   - 方案：以服务自身 config 为唯一权威——deploy yaml 改为由服务仓导出模板生成；CI 增加对拍门禁（每份 deploy yaml 必须能被对应服务 `LoadConfig` 接受，拒绝=流水线红）。
   - 工作量：门禁脚本 0.5 天 + 修齐现存漂移 0.5 天。

2. **别名层/跨仓拷贝的同步债务（A6 副作用）**
   - 现状：im 的 kitex_gen 别名层（orgcompat ~56 类型、file 38 类型）与 contracts 漂移只能靠文件头注释提醒；refaccess + fileservice 服务组自 ppb-file 拷贝，版本漂移无感知。
   - 方案：① contracts-file 发 tag（v0.2.x）→ service-file 成为 im 的合法依赖，撤两处拷贝；② CI 对拍：别名集 vs contracts 包导出符号反射 diff，漂移即红。
   - 工作量：①0.5 天（发 tag+改依赖+删拷贝）②1 天。

3. **生成器/运行时版本混用**
   - 现状：四服务 kitex_gen 头均为 `Generated by Kitex v0.16.3`，运行时 v0.16.4。当前无碍（0.16.3→0.16.4 兼容），但属于隐式假设。
   - 方案：装 kitex v0.16.4 CLI 重生成一轮四服务 stub（生成物 diff 应为零或极小），版本对齐后写入门禁。
   - 工作量：0.5 天。

### P1（架构完整度——迁移既定未完项）

4. **Phase C：出站内部调用 Kitex 客户端化（etcd 消费侧）**
   - 现状：etcd 只有注册没有发现消费；出站仍 grpc-go 直连 + RETRY_CONFIG 静态 JSON（有重试/轮询但无熔断、无实例摘除）。
   - 方案：camera→iam 先行试点（单依赖最薄）：grpc_dependencies 增 `service_name` 双写模式（有 service_name 走 kitex client + etcd resolver，否则回退 address 直连——灰度开关）；验证 LB/重试/熔断语义后推 file/im/iam。iam 侧注意 A2 保真件与 A4 actor 桥在 kitex 客户端下的等价物（metainfo→HTTP/2 头与 grpc-go metadata 的互通已验证，出站侧需同样核验）。
   - 工作量：试点 1 天 + 全量 2 天。

5. **冒烟工具只覆盖 im 主链**
   - 现状：smoke（ALL PASS 口径）只测 im；file/camera/iam 无同级闭环工具，检查手册 §3.4 对这三家只能用负例探针。
   - 方案：按 smoke 模式补三家冒烟（file：上传→登记→配额→回收站；camera：guest session→templates→quota；iam：qatokens 已具雏形，纳入工具化），统一 `cmd/smoke` 惯例与种子前置。
   - 工作量：每家 0.5 天。

6. **新旧二进制并存切换无 runbook**
   - 现状：`deploy/bin/*.kitex` 与旧版并存，常驻旧 im/file 仍跑旧 gRPC 二进制（与 Kitex IAM 互通正常，无功能故障）；切换靠手工。
   - 方案：写切换 runbook（停旧→起 *.kitex，env 集清单：PPB_INTERNAL_RPC_TOKEN/PPB_ALLOW_DEV_JWT/DSN/Redis）；`start-all.sh` 更新为 kitex 二进制；建议一次性切换后删旧 bin。
   - 工作量：0.5 天。

### P2（工程质量，不阻塞）

7. **config 键形不统一**：camera `rpc_port` vs file `grpc_port`；im 从 yaml 读 internal_token 而 camera 走 env。方案：config v2 规范一次清理批次（键名对齐 + env 优先级统一），随 P0-1 deploy 对拍门禁一起做。
8. **dynamicgo 警告刷屏**（darwin/arm64 性能降级提示）：反射路径正确性已验，接受；如需降噪可构建标签关闭。
9. **计时不稳测试**（多仓并行验证时 im 偶发抖动）：并行验证错峰或 `go test -p 1`；手册已写"先重跑再判"。
10. **gateway 维持 HTTP 反代的长期决策**：迁移设计即如此（136 路由风险）；若未来要收 RPC 跳数，重开决策评审，不默认执行。

---

## 三、预防性改进（跨批次沉淀）

1. **CI 门禁三件**（承接 D3/P0-1/P0-2）：contracts 仓纯净检查；deploy yaml 可加载对拍；别名集同步对拍。
2. **环境变量集单一来源**：`GOPROXY/GOPRIVATE/PATH/GOFLAGS` 与运行 env（token/JWT/DSN）各成一份脚本（`env/go-env.sh` + 启动脚本），杜绝 B4/D1 类手误。
3. **跨服务验证方法论**：业务码探针 + lsof 连接层证据双签（D2 教训），写进检查手册附录。
4. **并行子代理纪律**：报告以提交哈希核验（D7）；跨仓依赖的情报（如"某仓未发 tag"）在派工单里预先标注。
