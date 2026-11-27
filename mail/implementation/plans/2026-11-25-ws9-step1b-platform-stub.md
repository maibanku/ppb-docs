# WS9 第一步半任务书：平台替身和联调工具

> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md) 的第 1 节（怎么配合、上下文怎么省）、第 2 节（环境）和第 5 节（报告）。

## 身份

- 工作流：WS9 集成的准备工作。本机联调要让控制面以为自己在平台里：成员带着登录态来调接口、管理员经 IAM 的业务桥来调管理接口、对账去 IAM 和 IM 拉用户。本机那套真实的平台（IAM、IM）是别人正在用的，不能往里写测试数据，而且那套 IAM 是旧版本。所以要一个**平台替身**，再加一个**联调工具**替浏览器和网关发请求。
- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws9-harness`（worktree），分支 `feat/ws9-harness`。它从集成分支 `feat/ws9-integration` 的 05956c7 拉出来：已经有控制面的骨架、配置渲染、成员邮箱、投递与运维（账号与域名那一轮还没合进来，管理面里开通邮箱那些方法现在还是桩）。
- **不改 `service-mail/` 下已有的任何代码**，只新增。不改 `deploy/compose/`（联调编排由另一轮在做）。发现控制面的问题写进报告。
- 进度文件：`service-mail/docs/implementation/progress-harness.md`（新建，跟着提交）。

## 要读的

1. 平台 SDK 里和身份有关的三样（只读）：`/Users/pipi-ban/Desktop/code/vscode/ppb-base/platform-sdk/iam/svcauth/`（成员登录态的 JWT：HS256，`typ` 是 `member`，`sub` 是成员标识，`sid` 是会话锚；`claims.go`、`member.go`）、`…/authzport/iamassert.go`（IAM 业务桥的带签名断言：`SignIAMAssertion`、`ParseIAMAssertion`、`IAMContext`）、`/Users/pipi-ban/Desktop/code/vscode/ppb-base/go-framework/rpcx/interceptor/`（服务之间的内部凭据：环境变量 `PPB_INTERNAL_RPC_TOKEN`，放在 gRPC 的元数据里）。
2. 控制面怎么用它们：`service-mail/internal/transport/mail/`（根包的成员门；`manage/http.go` 的管理端登录态和权限复检，先认断言头 `X-Ppb-Iam-Assertion`，再认管理端 token）、`cmd/server/boot_wire.go`（出站客户端的装配）、`cmd/server/outbound.go`（出站连接的拨号选项）。
3. 控制面调了平台的哪些 RPC（**照代码里的调用写替身，不要照想象**）：
   - IAM 的 `IamService`：`ValidateSession`（成员会话复检，`internal/client/grpc/iam/iam.go`）、`InspectAccount`（成员邮箱查用户状态，`cmd/server/wire_mailbox.go`）、`ListUsers`（对账，`internal/accountsync/iam.go`）；
   - IAM 的 `AdminCompatService`：`AdminAuthz`、`RbacVersion`（管理端 token 那条路的权限复检）；
   - IM 的 `OrgCompatService`：`ResolveMembersByIds`（成员标识换用户标识，`internal/mailbox/identity.go` 和 `internal/accountsync/im.go`）、`ListMembers`（对账）；
   - IM 的 `ChatOrgService`：成员身份复检（`internal/client/grpc/im/chatorg.go`）。
   - 账号与域名那一轮合进来之后还会多一个按用户查状态的调用（`InspectAccount`），替身的数据要够它用。
   - 契约：IAM 的在 `/Users/pipi-ban/Desktop/code/vscode/ppb-iam-ws/mail-integration/contracts-iam/proto/`（`ListUsers` 在这个分支上才有，已发布的 tag 里没有）；IM 的在 `/Users/pipi-ban/Desktop/code/vscode/ppb-chat/contracts-im/proto/`。两个模块的依赖 `service-mail/go.mod` 里都已经有了。
4. IAM 真实实现的行为（替身要像它）：`ValidateSession` 成功时回什么、失败时是 gRPC 的状态错误；`ResolveMembersByIds` 按入参顺序返回、未命中给占位（`deleted=true`）；`InspectAccount` 的 `user_status` 取值 1 正常、2 停用、3 注销，查无是业务错误。看 `ppb-iam-ws/mail-integration/service-iam` 和 `ppb-chat` 里对应的实现，只读。

## 要做的东西

### 1. 平台替身 `service-mail/cmd/devplatform/`（只在开发和联调用，不进生产镜像）

一个 Go 程序，用 grpc-go 起上面四个服务的 gRPC 服务端（生成的服务描述符在契约模块里，把没用到的方法留给 `Unimplemented…Server`），实现下面这些方法：

| 方法 | 替身的行为 |
|---|---|
| `IamService.ValidateSession` | 会话标识在替身的有效会话表里就回成功，否则回 IAM 的业务错误（照真实实现的码） |
| `IamService.InspectAccount` | 按用户标识查用户，回 `user_id`、`user_status`、`identities`（至少一条 `provider=email` 的，给「初始密码设置成功的通知」用）；查无回业务错误 |
| `IamService.ListUsers` | 游标分页列出替身里的全部用户（含状态和更新时间），口径照 IAM 分支上的实现 |
| `AdminCompatService.AdminAuthz`、`RbacVersion` | 回一个超管、权限码全集的快照 |
| `OrgCompatService.ResolveMembersByIds` | 按入参顺序回，带 `userId`、`name`、`deleted` |
| `OrgCompatService.ListMembers` | 按部门列成员（`departmentId` 过滤），分页 |
| `ChatOrgService` 的成员身份复检 | 替身里的成员就回正常 |

- **数据是脚本化的，可以在运行时改**：启动时读一份 JSON 种子；再开一个只在联调网络里可达的 HTTP 控制口（比如 8080），给联调工具用：登记用户、给用户发一个会话、登记成员并绑到用户、停用用户、注销用户。控制口不需要认证，但**只监听容器里的地址、不发布到宿主机**（联调工具从容器网络里调，或者经编排只发布到 127.0.0.1——写清楚你选了哪种、为什么）。
- 内部凭据：真实的服务会校验 gRPC 元数据里的内部凭据。替身校验一下（环境变量 `PPB_INTERNAL_RPC_TOKEN` 非空时，请求没带或带错就回 `Unauthenticated`），这样联调能发现控制面没带凭据的问题。
- 不记任何口令、令牌到日志。
- 有单元测试（用 bufconn 或回环端口起真的 gRPC 服务端，逐个方法断言），不用 testify。

### 2. 替身的镜像 `deploy/images/platform-stub/`

照 `deploy/images/service-mail/` 的做法（先在本机编译，再拷进一个按摘要固定的最小运行镜像；构建脚本、说明）。镜像名 `ppb-mail/platform-stub:<标签>`。**不要**把它加进控制面的镜像。

### 3. 联调工具 `service-mail/cmd/e2etool/`（也只在联调用）

一个命令行程序，子命令至少有：

- `member-token`：按成员标识和会话标识签一个成员登录态（HS256，密钥取环境变量 `MAIL_JWT_SECRET`；`typ=member`、`sub`、`sid`、`exp`、`iss` 照配置）。**输出只打到标准输出的一行里**，供脚本capture，不写日志。
- `manage-assertion`：签一个 IAM 业务桥的断言（HMAC 的密钥取环境变量 `PPB_INTERNAL_RPC_TOKEN`；绑定串是 `HTTP <方法> <路径>`；主体是管理员用户标识；`IsSuper` 和各应用的权限码可以指定），输出 `X-Ppb-Iam-Assertion` 头的值。
- `call`：带上面两种凭据之一去调控制面：`call member <方法> <路径> [JSON 请求体]`、`call manage <方法> <路径> [JSON 请求体]`，把响应的状态码、响应头里要紧的几个和正文打到标准输出。地址取参数。流式的下载存成文件（`-o`）。
- `platform`：调替身的控制口登记数据（`platform add-user …`、`platform add-session …`、`platform bind-member …`、`platform disable-user …`）。

签出来的东西要有测试证明控制面认：用平台 SDK 的 `svcauth.NewValidator(...).Parse` 和 `authzport.ParseIAMAssertion(...)` 做往返断言（SDK 在 `service-mail/go.mod` 里）。

### 4. 说明

`service-mail/docs/e2e.md`（或并进进度文件）：替身实现了什么、没实现什么；联调工具怎么签、怎么调；在编排里怎么摆（替身两个 gRPC 端口给控制面用，控制口的可达范围）；已知和真实平台的差别（比如替身不校验成员是否真的属于某个组织）。

## 完成标准

- `GOWORK=off go build ./... && go vet ./... && go test ./...` 全绿，`gofmt -l .` 没有输出。两个新包各有测试。
- 替身的镜像构建成功（本机架构），容器起来之后四个 gRPC 服务都能应答（用 `grpcurl` 或联调工具验证，写进进度文件）。
- 没改 `service-mail/` 下已有的文件（`go.mod` 除外：确实要加依赖时在报告里说明）。
- 不碰本机的 `ppbmail-dev-*`、`ppbmail-e2e-*` 容器和 `ppb-mysql`；替身自己做验证用的一次性容器用完删掉。
- 提交都在 `feat/ws9-harness` 上，不推送，不合并。不要用 Agent 工具再派子 agent。

## 报告

按共用说明第 5 节。另外单列：替身每个方法的行为和真实 IAM、IM 的差别；联调工具的用法（几条命令）；和真实平台对接时可能对不上的地方（码、字段、分页口径）。
