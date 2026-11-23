# Kitex 落位地图（迁移终局盘点）

> 日期：2026-11-23 · 范围：Kitex 相关代码/依赖/生成物/运行态在六仓的完整落位
> 关联：`kitex-migration-plan.md`（方案）、`adr-gateway-http-proxy.md`（网关定案）

## 〇、树形总图

```text
vscode/                                        # 六仓工作区
├── ppb-base/                                  # 框架仓 —— 共享件层（仅 rpcx 与 iam SDK 沾 kitex）
│   ├── go-framework/rpcx/                     #   独立模块 tag v0.2.x（网关/根模块因此不沾）
│   │   ├── kitexmw/
│   │   │   ├── kitexmw.go                     #     服务端 Recovery/RequestID/InternalAuth/FullMethod
│   │   │   └── clientmw.go                    #     出站三中间件（requestid/internalauth/断言）
│   │   └── kitexstarter/server.go             #   Kitex server → boot.Component（组件名 "grpc"）
│   ├── platform-sdk/iam/authzport/            #   tag v0.2.2
│   │   └── iamassert_kitex.go                 #     客户端 IAM 断言按方法重签
│   └── deploy/config/*.yaml                   #   registry.etcd 段 + service_name 灰度键
│
├── ppb-chat/service-im/                       # @9102 —— serving 5 组 + 消费 iam/file
│   ├── kitex_gen/
│   │   ├── im/                                #   自 serving（别名层类型）
│   │   │   ├── imservice/ · chatorgservice/ · orgcompatservice/ · groupfileauthservice/
│   │   │   └── {im,orgcompat,chatorg,group_file_auth}.pb.go
│   │   ├── iam/                               #   消费（出站 kitex client）
│   │   │   ├── iamservice/ · iamaccountbridge/ · admincompatservice/
│   │   │   └── {iam,iamx,admincompat}.pb.go + alias_sync_test.go
│   │   ├── go/refaccess/refaccessservice/     #   自 serving（file 回调裁决）
│   │   ├── go/file/fileservice/               #   消费（smoke 桩）
│   │   ├── go/sync_test.go                    #   拷贝件 ↔ ppb-file 上游文件级对拍门禁
│   │   └── alias_parity_test.go               #   接口级 ↔ contracts 反射对拍门禁
│   ├── internal/transport/
│   │   ├── im/{im,chat_org,call,org_compat,org_compat_contacts,org_compat_profile,admin_authz}_kitex.go
│   │   ├── refaccess/ref_access_kitex.go
│   │   └── groupfileauth/group_file_auth_kitex.go
│   ├── cmd/server/boot_wire.go                #   kitexserver.NewServer 五组同注册 + kitexstarter
│   ├── cmd/smoke/main.go                      #   十步冒烟（Kitex 桩）
│   └── internal/config/im_config.go           #   registry.etcd + service_name 灰度
│
├── ppb-iam/service-iam/                       # @9107 —— serving 3 组 + 消费 im
│   ├── kitex_gen/iam/{iamservice,iamaccountbridge,admincompatservice}/   # 自 serving
│   ├── kitex_gen/im/{chatorgservice,orgcompatservice}/ + alias_sync_test.go  # 消费
│   ├── internal/transport/iam/
│   │   ├── {iam,account_bridge,admin_compat}_kitex.go
│   │   ├── iam_assertion_kitex.go             #   断言中间件 + legacy actor 桥
│   │   └── kitex_status_fidelity.go           #   ErrBiz 壳剥除（码/文案保真）
│   └── cmd/{server,smoke}/
│
├── ppb-file/service-file/                     # @9104 —— serving 2 组 + 消费 iam
│   ├── kitex_gen/go/{file,refaccess}/         #   自 serving（prutal 类型）
│   ├── kitex_gen/go/iam/admincompatservice/ + alias_sync_test.go            # 消费
│   ├── internal/transport/file/{file,file_upload,file_download,file_meta,file_manage}_kitex.go
│   └── cmd/{file,smoke}/
│
├── ppb-camera/service-camera/                # @9106 —— serving 2 组 + 消费 iam
│   ├── kitex_gen/camera/{cameraservice,adminservice}/   # 自 serving（prutal）
│   ├── kitex_gen/iam/admincompatservice/ + alias_sync_test.go              # 消费
│   ├── internal/transport/camera/{camera,camera_admin}_kitex.go
│   ├── cmd/server/{boot_wire,service_http_wire}.go     # kitex server + HTTP 契约面
│   └── cmd/smoke/main.go                      #   五步冒烟（含 Phase C 回源探针）
│
├── ppb-gateway/service-gateway/              # ✗ 无 kitex（ADR 定案：HTTP 反代）
└── contracts-{im,file,iam,camera}/           # ✗ 无 kitex（纯净铁律：仅 proto + gen/go）
```

运行态（非文件系统）：etcd `kitex/registry-etcd/ppbchat-<svc>/<ip>:<rpc-port>` ×4。

## 一、依赖落位（go.mod 层）——仅 6 个模块沾 kitex

| 模块 | 角色 | 发版 tag |
|---|---|---|
| `ppb-base/go-framework/rpcx` | 共享中间件 + boot 组件（`kitexmw/`：Recovery/RequestID/InternalAuth/FullMethodFromContext + `clientmw/` 出站三件；`kitexstarter/`） | `go-framework/rpcx/v0.2.x` |
| `ppb-base/platform-sdk/iam` | IAM 断言协议权威件（`authzport/iamassert_kitex.go`：客户端断言按方法重签中间件） | `platform-sdk/iam/v0.2.2` |
| `service-im` / `service-iam` / `service-file` / `service-camera` | 服务端 + 出站消费 | 随各仓 |

**不沾 kitex 的**（有意设计）：contracts ×4（纯净铁律——重依赖禁入，消费方免拉）；
gateway（ADR 定案 HTTP 反代）；`go-framework` 根模块（logx/boot/requestid 等被
网关与工具消费，不能被 kitex 污染——rpcx 独立模块即为此隔离，先例是 requestid
当年拆 grpc 依赖）；桌面/移动端（不感知 RPC 框架）。

## 二、生成物落位（kitex_gen 层）——自足式原则

**原则：每个服务模块自带它需要的全部 kitex 服务组（自己 serving 的 + 自己
消费的），跨仓零 kitex_gen 共享依赖。**

| 服务模块 | 自 serving 服务组 | 消费用服务组（出站/桩） |
|---|---|---|
| service-im | `kitex_gen/im/`{imservice, chatorgservice, orgcompatservice, refaccess†, groupfileauthservice}（五组一 server @9102） | `kitex_gen/iam/`{iamservice, iamaccountbridge, admincompatservice}；`kitex_gen/go/file/fileservice`（smoke 桩） |
| service-iam | `kitex_gen/iam/`{iamservice, iamaccountbridge, admincompatservice}（@9107） | `kitex_gen/im/`{chatorgservice, orgcompatservice} |
| service-file | `kitex_gen/go/`{file/fileservice, refaccess/refaccessservice}（@9104） | `kitex_gen/go/iam` |
| service-camera | `kitex_gen/camera/`{cameraservice, adminservice}（@9106） | `kitex_gen/iam/admincompatservice` |

† refaccess 契约权威在 contracts-file、服务端实现归 im（file 回调裁决）。

**类型面两种形态**：iam/file/camera = prutal 生成类型；im = **别名层**
（`type X = contracts.X`，业务层 34 文件零改动）+ 消费侧别名层（refaccess/file）
+ 跨仓同版拷贝服务组。跨仓重复由双门禁守：`kitex_gen/go/sync_test.go`
（文件级对拍 ppb-file 上游）+ `alias_parity_test.go`（接口级与 contracts
权威反射对拍）。

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

## 五、放置原则的取舍与演进触发

1. **contracts 纯净 > 生成物集中**：曾评估把 kitex_gen 放 contracts（单一生成
   点），被否——contracts 是全端消费的轻依赖仓，沾 kitex 会污染所有消费方。
   代价 = 跨仓拷贝，由同步门禁兜底。
2. **自足式 > 共享 stubs 模块**：服务模块自治（重构不跨仓、无发版联动）；
   代价 = 同一服务组最多两三份拷贝。
3. **演进触发**：当第三个消费方需要同一服务组、或拷贝份数使门禁噪声化时，
   重评「共享 stubs 模块」（如 ppb-base 新 kitexstubs 模块或 contracts 旁挂
   轻模块）；contracts 发版节奏显著加快时重评别名层维护成本。
