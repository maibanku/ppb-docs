# WS9 修正一任务书：对着真实平台会调不通的三处

> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md) 的第 1 节、第 2 节和第 5 节，再读 `/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws9-fixes/service-mail/docs/e2e.md`（平台替身的说明，里面有「和真实平台对不上的地方」的逐条表）。

## 身份

- 工作流：WS9 集成的修正。做平台替身的那一轮把控制面的调法对着真实的 IAM、IM 核了一遍，查出三处**在真实平台里会被拒或换错人**的问题。设计文档（ADR-003 第 8 节、tech/06 第 2 节、tech/09 第 2.3 节）把接口的方向写错了，下游照着实现，所以错在设计，不在实现的那两轮。文档由负责人去改，你改代码。
- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws9-fixes`（worktree），分支 `feat/ws9-fixes`（从集成分支 `feat/ws9-integration` 的 e571c58 拉出：骨架、配置渲染、成员邮箱、投递与运维、平台替身和联调工具都在；账号与域名那一轮还没合进来）。
- 进度文件：`service-mail/docs/implementation/progress-ws9-fixes.md`（新建，跟着提交）。
- 不合并别的分支，不推送。不改平台仓库（`ppb-chat`、`ppb-iam`、`ppb-base` 只读）。不碰本机的 `ppbmail-dev-*`、`ppbmail-e2e-*` 容器和 `ppb-mysql`。

## 事实（都是读真实代码核出来的，你自己再读一遍确认）

1. **成员登录态的主体是成员标识**：JWT 的 `sub` 是十进制的 `chat_membership_id`（`ppb-file/service-file/internal/httptunnel/member_gate.go` 的注释写了）。
2. **成员标识换用户标识用的是 `im.OrgCompatService/ResolveMemberIds`**，不是 `ResolveMembersByIds`：
   - 请求 `ResolveMemberIdsReq{ memberIds []string }`，应答 `pairs` 按入参序，`userId` 为 0 表示没命中。真实的实现在 `ppb-chat/service-im/internal/transport/im/org_compat_kitex.go`（`MembersByIdRefs`，按 `chat_membership_id IN` 查）。ppb-file 就是这么用的：`ppb-file/service-file/internal/client/grpc/im/user_grpc_client.go`。它是内部接口，不在 IM 的管理授权表里。
   - **`ResolveMembersByIds` 的方向是反的**：入参字段虽然叫 `memberIds`，真实的实现把它当**用户标识**（`MembersByIDs`，`WHERE user_id IN`），应答里 `user_id` 原样回入参、`member_id` 是查到的成员标识，`email`、`mailAddr` 不填。
   - 控制面现在的调法（成员邮箱 `internal/mailbox/identity.go`、对账 `internal/accountsync/im.go`）是把成员标识传给 `ResolveMembersByIds`、把应答的 `user_id` 当用户标识。对着真实 IM：要么全部未命中（成员面回 MAIL-3003），要么撞上另一个用户标识恰好等于这个数的用户——**换错人**，这是评审里最不能出的一类。
3. **`ListMembers` 是 IM 的管理接口**（`ppb-chat/service-im/internal/transport/im/admin_authz_policy.go`：要 `chat` 域的 `member.read`，身份取 `x-ppb-actor` 加 IAM 断言）。控制面的对账是后台任务，没有管理员身份，真实 IM 回 `PermissionDenied`。另外聊天产品已经转向 C 端，组织管理面退役了，「按组织开通」在当前平台没有数据。
4. **IAM 的 `InspectAccount` 是供给面的接口**（`ppb-iam-ws/mail-integration/service-iam/internal/transport/iam/iam_kitex.go` 的 `InspectAccount`）：要 IAM 断言加在册的管理员，只带内部凭据的调用回 `PermissionDenied`。平台给服务间调用配的出站拦截器是 `authzport.IAMAssertionClientInterceptor`（ctx 里有 IAMContext 时按当前方法重签断言；没有时什么都不做），ppb-file 的 `cmd/file/iam_outbound.go` 是先例。控制面的出站连接（`cmd/server/outbound.go` 的 `internalDialOpts`）没有挂它。

## 要做的（每件事一个或几个提交，测试先行）

### 修正 1：成员标识换用户标识（`internal/mailbox/identity.go`）

- 成员标识 → 用户标识改走 `ResolveMemberIds`（入参是十进制串）。没命中（`userId` 为 0）按现在的「换不出来」处理（503 MAIL-3003）。
- 显示名：拿到用户标识之后用 `ResolveMembersByIds` 按**用户标识**取 `name`（这是它的正确用法）。两次调用都进同一份缓存（5 分钟），没命中的照旧缓存 30 秒。
- 测试要按真实 IM 的语义写：起一个假的 gRPC 服务端（或者直接用平台替身 `cmd/devplatform/platformstub` 的 IM 那一半的 `real` 模式，看哪个省事），断言：
  - 成员标识 20001 → 用户标识 70001：换出来的用户标识是 70001；
  - 造一个「用户标识的数值等于另一个成员标识」的场景（用户 20001 真实存在，但不是这个成员），断言**不会**被换到它身上——这条是防回归的重点；
  - 没命中、服务不可达、应答长度和入参不一致时的行为。
- 骨架的 `internal/client/grpc/im` 不改（它只包了成员身份复检）；连接照成员邮箱那一轮现在的做法。

### 修正 2：对账里的「按组织」和对账的成员换用户（`internal/accountsync/`）

- 成员 → 用户的映射：`ListMembers` 的条目里有没有 `userId` 字段你自己看契约（`ManageMemberItem`）。有就直接用，没有就用 `ResolveMemberIds`。不再把成员标识传给 `ResolveMembersByIds`。
- `ListMembers` 的调用**保留**（平台哪天允许了就能用），但被拒时要说人话：IM 回的 `PermissionDenied`（gRPC 状态）和授权类的业务错误，映射成一句明确的业务错误，例如「按组织开通在当前平台不可用：IM 的成员列表是管理接口，后台任务调不了（要 chat 域 member.read 的管理员身份）」。定时对账遇到它时这一轮记为失败并带这句话（告警会响，这是对的：说明配了一个用不了的范围）。
- 自动开通范围是 `orgs` 但组织列表为空时（现在的缺省）：确认对账**不调** IM，只用 IAM 的用户做状态同步。不是这样就改成这样，加测试。
- 把这句话和判断写进 `internal/accountsync` 的包说明（`doc.go`），别让后来的人以为这个范围能用。

### 修正 3：IAM 出站带上断言（`cmd/server/outbound.go`）

- 给连 IAM 的那条出站连接挂上 `authzport.IAMAssertionClientInterceptor(internalauth.Token)`（放在内部凭据的拦截器之后）。连 IM 的那条不挂（IM 的管理接口要的是 `x-ppb-actor`，不是这条路）。
- 读一遍挂了之后有没有副作用：ctx 里没有 IAMContext 的调用（成员会话复检、成员邮箱查登录邮箱）必须和原来一模一样。
- 账号与域名那一轮合进来之后，它查用户状态（`InspectAccount`）要靠这个拦截器，并且调用时的 ctx 里要带着管理员的 IAMContext。那一轮还没合进来，你在进度文件里给负责人留一条提醒。
- 成员邮箱「设置初始密码成功后通知 IAM 的登录邮箱」那条路（`cmd/server/wire_mailbox.go` 里调 `InspectAccount` 的地方）：调用方是成员，没有管理员的上下文，**真实 IAM 会回 `PermissionDenied`**。确认这种情况下的行为是：设置初始密码照常成功，通知不发，记一条说明原因的日志，不报错给用户。是这样就补一条测试钉住；不是就改成这样。
- 测试：假 IAM 服务端要求「带合法断言才放行」，不带断言回 `PermissionDenied`；断言经管理面进来时（ctx 有 IAMContext）出站调用能过，成员面进来时能过内部凭据但被 IAM 以 `PermissionDenied` 拒掉且业务不受影响。

### 修正 4：用平台替身的 `real` 模式做一遍回归

平台替身有 `lenient`（照控制面原来的调法应答）和 `real`（照真实平台设卡）两种模式。加一组测试（或者在 `docs/e2e.md` 里写明怎么做、并实际做一遍记进进度文件）：**控制面在 `real` 模式下，成员标识换用户标识换得对，成员面的身份映射走得通**。替身的 `lenient` 模式如果让「把成员标识传给 `ResolveMembersByIds`」也能过，考虑把它收紧成和真实一致（这样别的测试不会再带着错误的调法通过）；要改替身的话把依赖它的测试一并改对，并说明。

## 完成标准

- `GOWORK=off go build ./... && go vet ./... && go test ./...` 全绿，`gofmt -l .` 没有输出。
- 修正 1 有「不会换错人」的防回归测试；修正 3 有「不带动 IAMContext 的调用行为不变」的测试。
- 平台替身在 `real` 模式下，控制面的身份映射是通的（有测试或进度文件里的实测记录）。
- 提交都在 `feat/ws9-fixes` 上，不推送。不要用 Agent 工具再派子 agent。

## 报告

按共用说明第 5 节。另外单列：每一处修正前后控制面的调用是什么样的；你发现的、这三处之外的对不上的地方；留给负责人的事（文档里要改的句子、账号与域名那一轮要注意的）。
