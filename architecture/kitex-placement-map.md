# Kitex 落位地图（迁移终局盘点 · 方案 B 终态）

> 日期：2026-11-23 · 更新：2026-11-24（方案 B：kitexstubs 旁挂模块收口）
> 范围：Kitex 相关代码/依赖/生成物/运行态在六仓的完整落位
> 关联：`kitex-migration-plan.md`（方案）、`adr-gateway-http-proxy.md`（网关定案）
> 沿革：方案 B 之前的「自足式 kitex_gen」落位见本文件 git 历史（ppb-docs `d7b60c2` 及之前）

## 〇、树形总图（方案 B 终态）

```text
vscode/                                          # 六仓工作区
├── ppb-base/                                    # 框架仓 —— 共享件层（仅 rpcx 与 iam SDK 沾 kitex）
│   ├── go-framework/rpcx/                       #   独立模块 tag v0.2.x（网关/根模块因此不沾）
│   │   ├── kitexmw/
│   │   │   ├── kitexmw.go                       #     服务端 Recovery/RequestID/InternalAuth/FullMethod
│   │   │   └── clientmw.go                      #     出站三中间件（requestid/internalauth/断言）
│   │   └── kitexstarter/server.go               #   Kitex server → boot.Component（组件名 "grpc"）
│   ├── platform-sdk/iam/authzport/              #   tag v0.2.2
│   │   └── iamassert_kitex.go                   #     客户端 IAM 断言按方法重签
│   └── deploy/config/*.yaml                     #   registry.etcd 段 + service_name 灰度键
│
├── ppb-chat/
│   ├── contracts-im/                            # 契约根模块 v0.2.0（✗ 不沾 kitex：proto + gen/go）
│   │   ├── gen/go/im/                           #   protoc-gen-go 消息类型（全端消费的权威）
│   │   └── kitexstubs/                          # ★ 旁挂模块 tag contracts-im/kitexstubs/v0.1.0
│   │       ├── go.mod                           #     module …/contracts-im/kitexstubs → 根模块 + kitex
│   │       └── im/                              #     别名层 258 类型（type X = contracts.X）
│   │           ├── {im,orgcompat,group_file_auth}.pb.go     # kitex 编解码/服务信息
│   │           └── imservice/ · chatorgservice/ · orgcompatservice/ · groupfileauthservice/
│   └── service-im/                              # @9102 —— serving 5 组 + 消费 iam/file（✗ 无 kitex_gen）
│       ├── internal/transport/
│       │   ├── im/{im,chat_org,call,org_compat,org_compat_contacts,org_compat_profile,admin_authz}_kitex.go
│       │   ├── refaccess/ref_access_kitex.go
│       │   └── groupfileauth/group_file_auth_kitex.go
│       ├── cmd/server/boot_wire.go              #   kitexserver.NewServer 五组同注册 + kitexstarter
│       ├── cmd/server/kitex_parity_test.go      #   九组接口级方法集对等锁（复盘 P0-2 复归）
│       ├── cmd/smoke/main.go                    #   十步冒烟（Kitex 桩）
│       └── internal/config/im_config.go         #   registry.etcd + service_name 灰度
│
├── ppb-iam/
│   ├── contracts-iam/                           # 契约根模块 v0.1.2（✗ 不沾 kitex）
│   │   ├── gen/go/iam/
│   │   └── kitexstubs/                          # ★ 旁挂模块 tag contracts-iam/kitexstubs/v0.1.0
│   │       └── iam/                             #     别名层 67 类型
│   │           ├── {iam,iamx,admincompat}.pb.go
│   │           └── iamservice/ · iamaccountbridge/ · admincompatservice/
│   └── service-iam/                             # @9107 —— serving 3 组 + 消费 im 2 组（✗ 无 kitex_gen）
│       ├── internal/transport/iam/
│       │   ├── {iam,account_bridge,admin_compat}_kitex.go
│       │   ├── iam_assertion_kitex.go           #   断言中间件 + legacy actor 桥
│       │   └── kitex_status_fidelity.go         #   ErrBiz 壳剥除（码/文案保真）
│       └── cmd/{server,smoke}/
│
├── ppb-file/
│   ├── contracts-file/                          # 契约根模块 v0.1.1（✗ 不沾 kitex）
│   │   ├── gen/go/{file,refaccess}/
│   │   └── kitexstubs/                          # ★ 旁挂模块 tag contracts-file/kitexstubs/v0.1.1
│   │       ├── file/                            #     别名层 47 类型 + file.pb.go + fileservice/
│   │       └── refaccess/                       #     别名层 2 类型 + refaccess.pb.go + refaccessservice/
│   └── service-file/                            # @9104 —— serving 2 组 + 消费 iam（✗ 无 kitex_gen）
│       ├── internal/transport/file/{file,file_upload,file_download,file_meta,file_manage}_kitex.go
│       └── cmd/{file,migrate,smoke}/
│
├── ppb-camera/
│   ├── contracts-camera/                        # 契约根模块 v0.1.1（✗ 不沾 kitex；暂无 kitexstubs）
│   └── service-camera/                          # @9106 —— serving 2 组 + 消费 iam
│       ├── kitex_gen/camera/                    # 自 serving（prutal 自有类型）——唯一存留的 kitex_gen
│       │   ├── camera_kitex.pb.go
│       │   └── {cameraservice,adminservice}/{…,client,server}.go
│       ├── internal/transport/camera/{camera,camera_admin}_kitex.go
│       ├── cmd/server/{boot_wire,service_http_wire}.go     # kitex server + HTTP 契约面
│       └── cmd/smoke/main.go                    #   五步冒烟（含 Phase C 回源探针）
│
└── ppb-gateway/service-gateway/                # ✗ 无 kitex（ADR 定案：HTTP 反代）
```

运行态（非文件系统）：etcd `kitex/registry-etcd/ppbchat-<svc>/<ip>:<rpc-port>` ×4。

## 一、依赖落位（go.mod 层）——9 个模块沾 kitex

| 模块 | 角色 | 发版 tag |
|---|---|---|
| `ppb-base/go-framework/rpcx` | 共享中间件 + boot 组件（`kitexmw/`：Recovery/RequestID/InternalAuth/FullMethodFromContext + `clientmw/` 出站三件；`kitexstarter/`） | `go-framework/rpcx/v0.2.x` |
| `ppb-base/platform-sdk/iam` | IAM 断言协议权威件（`authzport/iamassert_kitex.go`：客户端断言按方法重签中间件） | `platform-sdk/iam/v0.2.2` |
| `contracts-im/kitexstubs` | IMService / ChatOrgService / OrgCompatService / GroupFileAuthService 服务组 + 别名层 258 类型 | `contracts-im/kitexstubs/v0.1.0` |
| `contracts-iam/kitexstubs` | IamService / IamAccountBridge / AdminCompatService 服务组 + 别名层 67 类型 | `contracts-iam/kitexstubs/v0.1.0` |
| `contracts-file/kitexstubs` | FileService / RefAccessService 服务组 + 别名层 47 + 2 类型 | `contracts-file/kitexstubs/v0.1.1` |
| `service-im` / `service-iam` / `service-file` / `service-camera` | 服务端 + 出站消费 | 随各仓 |

**不沾 kitex 的**（有意设计）：contracts **根**模块 ×4（纯净铁律不变——重依赖
禁入，全端消费方免拉；kitex 只进旁挂的 kitexstubs 子模块）；gateway（ADR 定案
HTTP 反代）；`go-framework` 根模块（logx/boot/requestid 等被网关与工具消费，
不能被 kitex 污染——rpcx 独立模块即为此隔离，先例是 requestid 当年拆 grpc
依赖）；桌面/移动端（不感知 RPC 框架）。

## 二、生成物落位——kitexstubs 旁挂模块（方案 B）

**原则：每个契约仓旁挂一个 `kitexstubs` 独立 module，是该契约全部 kitex
服务组的单一生成点。服务仓不再持有任何 kitex 服务组拷贝，按需 require。**

依赖方向：服务仓 → `contracts-X/kitexstubs` → 根 contracts 模块（类型）+ kitex
运行时。不沾 kitex 的消费方（网关、桌面、移动端）仍只依赖根模块。

| kitexstubs 模块 | 服务组 | serving 方 | 消费方（出站/桩） |
|---|---|---|---|
| `contracts-im/kitexstubs` | imservice / chatorgservice / orgcompatservice / groupfileauthservice | service-im（与 refaccess 五组一 server @9102） | service-iam（chatorg / orgcompat） |
| `contracts-iam/kitexstubs` | iamservice / iamaccountbridge / admincompatservice | service-iam（@9107） | service-im、service-file、service-camera |
| `contracts-file/kitexstubs` | fileservice / refaccessservice | service-file（fileservice @9104）；service-im（refaccessservice†） | service-im（fileservice 冒烟桩） |
| （暂无） | cameraservice / adminservice | service-camera（@9106，`service-camera/kitex_gen/camera` 自足） | — |

† refaccess 契约权威在 contracts-file、服务端实现归 im（file 回调裁决）。

**类型面**：kitexstubs 全部为**别名层**（`type X = contracts.X`，覆盖 proto 包内
全部导出消息与枚举类型），handler/客户端签名与 gRPC 版同形，业务层零改动；
仅 camera 自 serving 仍为 prutal 生成类型。

**门禁分层**：

- 拷贝级同步门禁（`sync_test.go`、`alias_sync_test.go` ×4）——守「跨仓拷贝件与
  上游逐字一致」，拷贝既亡，全部退役。
- 接口级对等锁 `service-im/cmd/server/kitex_parity_test.go`——九组 kitex 服务接口
  ↔ contracts 权威接口方法集对等（contracts 抬版而 kitexstubs 未跟时立刻红，否则
  新方法静默不被伺服、编译期无感）。须留在消费方进程：kitexstubs 模块自身的
  测试不随依赖方执行。

## 三、业务代码落位（各服务模块内）

- **处理器**：`internal/transport/**/*_kitex.go`（gRPC 版已删，git 历史可溯）
- **服务端装配**：`cmd/*/boot_wire.go`——`kitexserver.NewServer`（WithListener
  fail-fast + WithExitWaitTime + WithServerBasicInfo + registry.etcd 非空才
  WithRegistry）+ `kitexstarter.Wrap(WithName("grpc"))`（停机序口径不变）
- **服务端中间件链**：kitexmw 共享三件 + 各服务自有鉴权中间件
  （camera Principal/AdminAuthz、file 双通道授权、iam 断言+保真件、im AdminAuthz）
- **配置**：`registry.etcd.endpoints`（空=直连模式）+ `KitexServiceName`
  （ppbchat-{im,iam,file,camera}）+ Phase C 出站灰度键
  `grpc_dependencies.<dep>.service_name`（空=grpc-go 直连回退）
- **出站消费（Phase C）**：消费面本地最小接口 + 薄包（kitex client +
  etcd resolver + 重试/熔断 + clientmw 三中间件）
- **冒烟**：`cmd/smoke` ×4（im 十步/file 十四步/camera 五步/iam 双路）

## 四、运行态落位

- etcd 键：`kitex/registry-etcd/ppbchat-<svc>/<lan-ip>:<rpc-port>`（lease
  keepalive，停机反注册）
- 标准口：9102(im)/9104(file)/9106(camera)/9107(iam)，netpoll+detection
  同口承载 gRPC 线缆（grpc-go 与 kitex 客户端皆可入）
- 启动/切换：`ppb-base/deploy scripts start-all`（源码构建 + mtime 判旧自动换新）

## 五、放置原则的取舍与演进触发（决策史）

> 2026-11-24 更新：§五.3 的演进触发条件成立，已按 §六 执行；以下保留为决策依据。

1. **contracts 纯净 > 生成物集中**：曾评估把 kitex_gen 放 contracts 根模块（单一
   生成点），被否——contracts 是全端消费的轻依赖仓，沾 kitex 会污染所有消费方。
   方案 B 的解法是「旁挂子模块」：纯净铁律对根模块原样保留，kitex 只进
   kitexstubs，不沾 kitex 的消费方免拉。
2. **自足式 > 共享 stubs 模块**（已取代）：服务模块自治（重构不跨仓、无发版
   联动）的代价是同一服务组最多两三份拷贝 + 双门禁噪声。
3. **演进触发**（已触发）：当第三个消费方需要同一服务组、或拷贝份数使门禁
   噪声化时，重评「共享 stubs 模块」——落地形态即 §六。contracts 发版节奏
   显著加快时，仍需重评别名层维护成本。

## 六、方案 B 执行实录（2026-11-24：kitexstubs 旁挂模块收口）

契约仓旁挂 `kitexstubs` 独立 module（依赖方向 kitexstubs → 根 contracts 类型 +
kitex 运行时），消灭跨仓拷贝与拷贝级同步门禁。三批全部完成，tag 均已推远端。

| 批次 | 模块（tag → 提交） | 消费方切换 | 状态 |
|---|---|---|---|
| 1（试点） | `contracts-file/kitexstubs` v0.1.0@`034a632` → v0.1.1@`b279fbe`（别名补全 9 个列表项） | service-file@`02a4687`（serving + 消费，prutal→contracts 类型）、service-im@`03f9fa1a`（refaccess serving + file 冒烟桩；`sync_test` 退役） | ✅ |
| 2 | `contracts-iam/kitexstubs` v0.1.0@`df94996`（别名补全 11 个嵌套项） | service-iam@`dcff9c6`（serving）、service-file@`9eb1e45`、service-im@`635316a8` | ✅ |
| 3 | `contracts-im/kitexstubs` v0.1.0@`7f45ad6f`（别名补全 0——256 消息 + 2 枚举类型原本即全量） | service-im@`95d1c282`（serving 四组；`kitex_gen/` 整目录 16 文件删除）、service-iam@`1ff1fa4`、service-camera@`0d8e41e`（main，经临时 worktree） | ✅ |
| — | `contracts-camera/kitexstubs` | — | 暂缓（见残留 1） |

**对等锁复归**：批次 3 删整目录时，复盘 P0-2 的 `alias_parity_test.go` 随之消失
（拷贝级门禁应退役，接口级对等锁不应）。已复归为
`service-im/cmd/server/kitex_parity_test.go`（ppb-chat@`e3d49030`），九组全部
对拍 kitexstubs；红绿验证：错配一对必红（逐方法报差），复原全绿。

**独立复验**（2026-11-24，非执行代理自述）：

| 服务 | build + vet | `go test -count=1 ./...` | 预存红 |
|---|---|---|---|
| service-im | exit 0 | 24 包 ok / 0 FAIL | — |
| service-iam | exit 0 | 19 ok / 1 FAIL | `internal/config TestDeployYamlLoadable` |
| service-file | exit 0 | 10 ok / 1 FAIL | `cmd/file TestDeployYamlLoadable` |
| service-camera（main） | exit 0 | 14 ok / 1 FAIL | `internal/service TestDeployYamlLoadable` |

三条预存红均非方案 B 引入，同因 = deploy 配置兼容门禁的**跨仓时序倒置**
（ppb-base 先登记新键、服务侧字段在未合并分支），各自分支合并后自愈：
iam `manage_jwt_secret`（feat/bridge-retire-manage-token）、file
`presign_endpoint`（feat/presign-direct-upload）、camera `http_enabled`
（ppb-base@`27023f4` 先登记，字段在 feat/contracts-api-home@`60e0d9b`）。

**残留与后续**：

1. `service-camera/kitex_gen/camera`（7 文件，prutal 自有类型）——唯一存留的
   kitex_gen；唯一消费方是 camera 自己，无跨仓拷贝价值。待
   feat/contracts-api-home 合并后评估是否上收 `contracts-camera/kitexstubs`
   （届时四仓同构）。该分支未触碰 `kitex_gen/` 与 `iam_outbound.go`，合并后
   旧 `kitex_gen/iam` 引用随 main 版本替换。
2. `service-im/go.mod` 的 `replace contracts-im => ../contracts-im`（群文件
   开发桥，注释「发版后撤」）：`contracts-im/v0.2.0` 已发且与 main 的 gen 目录
   零漂移，撤除条件已满足；该桥会把 kitexstubs 的传递依赖一并指到本地目录。
3. 注释残留：im/iam/file 三仓 transport、boot、smoke 的注释里仍有约 14 行
   「kitex_gen」历史表述（非 import，不影响构建），随手清。
4. 嵌套模块 tag 拉取慢：从 ppb-chat 拉 kitexstubs 新 tag 的浅 fetch 约 30MB
   （执行代理实测本批约 10 分钟），后续每次发 tag 都会遇到。

**关键经验**：

- 别名层必须覆盖 proto 包内**全部**导出消息与枚举类型（服务组生成件只引用
  顶层 Req/Resp，全量 handler 需要嵌套项类型——file 补 9 个、iam 补 11 个）。
- 类型形态统一为 contracts 类型后，iam/file 的 handler 从 prutal 自有类型切回
  contracts 类型，方法体同形、import 级改动；prutal 在 im/iam/file 三仓随被删
  生成件由 direct 降为 indirect。
- import 重写范围小于预估：service-im 业务层（service/realtime/call/clients）
  本来就直接 import contracts 根模块，实际只改 transport 9 文件 + boot_wire /
  smoke / e2e 3 文件。
- 删整目录会附带删掉其中的门禁：收口清单须逐文件区分「拷贝级（应退役）」与
  「接口级（须复归）」。
