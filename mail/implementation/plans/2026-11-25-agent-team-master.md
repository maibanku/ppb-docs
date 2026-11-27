# 邮箱系统实施总计划（agent 团队）

> 给参与实施的 agent：每个工作流由一个独立 agent 在自己的 worktree 里执行，负责人（主会话）负责排序、合并和验收。逐步任务在自己的分支上按测试驱动做：先写失败的测试，看到它失败，再写实现，再跑全部测试。进度写进各自 worktree 的 `docs/implementation/progress-<工作流>.md`。

**目标**：把 `ppb-docs/mail` 里的设计落成可运行的代码：控制面服务 service-mail、成员网页客户端、管理端插件、邮件核心镜像与编排，以及通知邮件的缺口修复。

**架构**：Postfix、Dovecot、Rspamd 负责邮件协议和投递，自研控制面 service-mail 管账号、域名、设置，并以 IMAP 客户端和提交者的身份为成员 HTTP 接口服务。成员网页客户端只调 HTTP 接口。详见 `ppb-docs/mail/tech/03-总体架构.md`。

**技术栈**：后端 Go，沿用平台的 go-framework、platform-sdk、Kitex 契约和目录规范；网页客户端 Vue 3、TypeScript、Vite；管理端插件基于 base-manage-web；邮件核心用 Docker 镜像和 Compose。

**依据**（按优先级）：

| 内容 | 位置 |
|---|---|
| 产品需求、功能点、阶段 | `ppb-docs/mail/PRD.md` |
| 规则细则 | `ppb-docs/mail/pr/03` 到 `pr/07` |
| 技术设计 | `ppb-docs/mail/tech/03` 到 `tech/11` |
| 接口操作清单和错误码 | `ppb-docs/mail/tech/09-接口契约.md` |
| 表结构 | `ppb-docs/mail/tech/sql/schema.sql` |
| 架构决策 | `ppb-docs/mail/adr/001` 到 `adr/006` |
| 网页客户端设计稿 | `ppb-mail/docs/design/README.md` 和 `screens/` |
| 平台约定（调研产出） | `ppb-mail/docs/conventions/*.md` |
| 运维代理协议 | `ppb-mail/docs/mailops-protocol.md` |
| 验收标准 | `ppb-docs/mail/ac/02-邮箱系统验收标准.md` |

---

## 全局约束

每个工作流都要遵守。

1. **仓库和分支**。新仓库 `ppb-mail`（本地，不建远端，不推送）。每个工作流在自己的 worktree 和分支上做：`git -C /Users/pipi-ban/Desktop/code/vscode/ppb-mail worktree add ../ppb-mail-ws/<工作流> -b <分支名>`，分支名见各工作流。只改自己工作流拥有的路径。
2. **共享仓库只开分支**。ppb-iam、ppb-chat、ppb-base、ppb-gateway 是别人也在用的仓库：只在各自的 worktree 里开分支改，不提交到 main，不推送，不合并。
3. **风格照平台**。后端严格按 `docs/conventions/backend-service-conventions.md`、`build-deploy-conventions.md` 和 `ppb-docs/architecture/05-后端服务内部目录规范.md`，参照 ppb-file/service-file。前端按 `docs/conventions/frontend-conventions.md`，成员网页客户端按设计稿。
4. **测试先行**。没有先失败的测试就不写实现。每个包都有测试。提交前跑所在模块的全部测试。
5. **接口口径**：标识是字符串，时间用 RFC3339 的 UTC，枚举用 int32，错误码用 MAIL 加四位数字。信封、分页、幂等键按 `tech/09` 第 2 节。
6. **秘密不进代码**：凭据只从环境变量来。示例数据只用 example.com、example.org、example.net。
7. **提交**：conventional commits，中文主题，一个提交只做一件事，每个提交都能通过测试。提交信息末尾加 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`。
8. **如实报告**。没跑的验证写没跑。卡住了写清楚卡在哪、试过什么，不要把没做完的写成做完。
9. **环境**：
   - Go 1.26 在 `/Users/pipi-ban/sdk/go1.26.0/bin`，可能不在 PATH。Go 模块一律 `GOWORK=off`。私有模块需要 `GOPRIVATE=github.com/maibanku/*,github.com/ppbchat/*`。
   - 前端用 Node 24（`/Users/pipi-ban/.nvm/versions/node/v24.21.0/bin`）。Node 25 会让 vue-tsc 报假的类型错误。
   - 本机代理会劫持回环地址的请求，跑本地服务前清掉 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`，或设 `NO_PROXY=127.0.0.1,localhost`。
   - Docker 可用。拉镜像失败时在镜像名前加 `docker.m.daocloud.io/`。本机 3306 上跑着别人也在用的开发库容器，不要动它；需要 MySQL 时自己另起一个容器。
10. **不要做的事**：不改 `ppb-docs`；不改共享仓库的 main；不建远端仓库；不删除 worktree 之外的任何东西。

## 评审时重点看

设计和测试最容易漏、真出问题又最伤用户的五类情况。每个工作流做完后，评审按这五条对照：

1. **开放中继和可信提交端口**：未认证向外部投递必须被拒；内部提交端口只能被控制面访问；控制面提交前必须校验发件地址归属。
2. **跨邮箱访问**：用别人的邮件、文件夹、附件标识访问，一律 404；主账号登录不被记成用户登录。
3. **秘密外泄**：日志、错误信息、配置摘要、审计里不能出现密码、口令、私钥、完整连接串。
4. **并发下的重复**：同一个幂等键并发只发一封；两个请求同时申请同一个地址只成功一个。
5. **密码哈希能被 Dovecot 验证**：控制面写入的哈希，邮件核心里的 Dovecot 能认。

---

## 工作流总览

| 编号 | 工作流 | 分支 | 依赖 | 拥有的路径 |
|---|---|---|---|---|
| WS0a | 契约 | `feat/ws0a-contracts` | 调研 | `contracts-mail/`、`api/policies/mail.yaml` |
| WS0b | 服务骨架 | `feat/ws0b-skeleton` | WS0a | `service-mail/` 骨架、`.github/`、`README.md` |
| WS1 | 后端·账号与域名 | `feat/ws1-be-admin` | WS0b | `service-mail/internal/{maildomain,mailaccount,blocklist}/`、管理接口的域名到审计各组 |
| WS2 | 后端·成员邮箱 | `feat/ws2-be-mailbox` | WS0b | `service-mail/internal/{mailbox,mailsetting,mailnotify}/`、`platform/{imap,smtpsubmit}/`、成员接口 |
| WS3 | 后端·投递与运维 | `feat/ws3-be-ops` | WS0b | `service-mail/internal/{outbound,delivery,mailqueue,accountsync,mailstatus}/`、`transport/postfixpolicy/`、`platform/{mailops,rspamd}/`、管理接口的限额到状态各组 |
| WS4 | 邮件核心与编排 | `feat/ws4-infra` | WS0b | `deploy/`、`service-mail/internal/render/` |
| WS5 | 成员网页客户端 | `feat/ws5-ui` | WS0a | `ui/` |
| WS6 | 管理端插件 | `feat/ws6-admin-web` | WS0a | `mail-manage-web/` |
| WS7 | 通知邮件缺口 | `fix/notify-mail-gaps`（ppb-iam、ppb-chat） | 无 | 两个共享仓库的各自分支 |
| WS8 | 平台接入 | `feat/mail-integration`（ppb-base、ppb-gateway） | WS0a | 两个共享仓库的各自分支 |
| WS9 | 集成 | `main` | 以上全部 | 合并、联调、总评审 |

依赖顺序：WS0a → WS0b → WS1 到 WS8 并行 → WS9。WS5、WS6、WS7、WS8 只依赖 WS0a 或不依赖，可以和 WS0b 同时开始。

工作流之间只通过下面两样东西耦合，先读它们再动手：

- `contracts-mail/`：proto 里的 RPC 和消息是所有后端工作流的共同接口。
- `service-mail/docs/implementation/wiring-plan.md`（WS0b 产出）：每个包归谁、启动装配的接缝在哪、工作流之间用哪些接口对接。

工作流之间需要调用对方能力时，在自己这一侧定义一个小接口，测试里用假实现，装配时由 WS9 接上。不要在自己的分支里实现别人的包。

待补充（调研完成后填写）：各模块的构建和测试命令、契约再生命令。

---

## WS7 通知邮件缺口（已先行启动）

不依赖任何其他工作流，所以最先启动。做法、提交顺序、测试名全部照 `ppb-docs/mail/tech/11-通知邮件缺口修复设计.md`，这里不重复。

| 仓库 | worktree | 分支 | 内容 |
|---|---|---|---|
| ppb-iam | `../ppb-iam-ws/notify-mail-gaps` | `fix/notify-mail-gaps` | 设计第 13 节的第 1 到 8 个提交 |
| ppb-chat | `../ppb-chat-ws/notify-mail-gaps` | `fix/notify-mail-gaps` | 第 9 个提交，推送记录页 |

完成标准：

- 九个提交都在各自的分支上，每个提交之前所在模块的测试通过。
- service-iam 的全部测试通过（记录命令和通过数）；chat-manage-web 的类型检查和测试通过。
- 设计第 15 节列的核对事项有结论。
- 「在 MySQL 测试库上用 EXPLAIN 确认索引」这一步没有测试库，标成没做。

## WS4 邮件核心与编排（已先行启动）

只做 `deploy/` 和 `docs/verification/`。控制面一侧的代码不在内。

拥有：`deploy/images/mailcore/`（mailops 模块、Dockerfile、入口脚本）、`deploy/config/{postfix,dovecot,rspamd}/`、`deploy/compose/`、`deploy/scripts/`、`deploy/docs/`、`docs/verification/M1-技术核对.md`。

任务（按顺序，每块做完提交）：

1. mailops：照 `ppb-mail/docs/mailops-protocol.md` 实现，单元测试加临时套接字的端到端测试。
2. 邮件核心镜像：Postfix 和 Dovecot 的配置照 `tech/05` 落地；数据库连接只引用 `/run/mail-config/` 里由控制面渲染的文件；日志写文件；等证书和配置再启动。
3. Rspamd 覆盖配置。
4. 编排：邮件节点编排、本机验证用的编排（自带 MySQL 和开发数据）、环境变量样例、自签证书脚本。
5. 脚本和文档：启动、停止、备份、恢复；`control-plane-contract.md`；`log-samples.md`；`runbook.md`。
6. 技术核对：用真实软件逐项核对 `tech/04`、`tech/05`、`tech/07`、`tech/10` 里和邮件核心有关的条目，结论只有三种。

完成标准：

- mailops 的测试通过，镜像构建成功。
- 技术核对表每一项都有结论和证据；没核对成的如实标出。
- 控制面要接手的事在 `control-plane-contract.md` 里写全。
- 验证用的容器已清理，没有碰本机 3306 上的开发库。

WS4 之后还有一步：骨架合入后，在 service-mail 里实现按模板渲染 Postfix、Dovecot、Rspamd 配置文件的包。这一步等 WS0b 完成后单独安排。

---

## WS0a 契约

直接在 `main` 的主检出里做（WS0a 单独跑，没有并发）。

拥有：`contracts-mail/`、`api/policies/`、`.github/workflows/ci.yml` 的契约检查部分。

已经定下的取舍：

- proto 字段名用小驼峰，照 contracts-file。
- HTTP 契约分三份：`mail-member-http.json`（member，36 条）、`mail-manage-http.json`（manage，55 条）、`mail-public-http.json`（匿名，1 条：转发地址确认）。
- 四个流式接口不进契约 JSON、不定义 RPC：附件上传、附件下载、原邮件下载、投递日志导出。写成 `contracts-mail/api/streaming-routes.md`。
- 管理接口的权限对象用 `appKey: "chat"` 加 `bridgeAppKey: "mail"`。平台的 authzguard 只认 base、chat、camera。
- 路径参数和查询参数全部显式写 `bindings`。平台不会按字段名自动绑定。
- RPC 服务名 `mail.MailboxService` 和 `mail.MailAdminService`。

任务：

1. `contracts-mail/proto/mail.proto`：两个服务、全部 RPC 和消息，注释带规则编号。
2. `buf generate` 产出并提交；`kitexstubs` 旁挂模块，做法照 contracts-file。
3. 模块文件：`go.mod`、`buf.yaml`、`buf.gen.yaml`、`_vendor/common.proto`、`tools/common-sync.sh`。
4. 三份 HTTP 契约 JSON、Go 访问器 `api/api.go`、`streaming-routes.md`。
5. `api/policies/mail.yaml` 和说明。
6. CI 的契约检查：两个 Go 模块各构建、vet、测试；`buf generate` 重跑无差异；common.proto 同步检查。
7. `contracts-mail/README.md`。

完成标准：

- `buf generate --path proto/mail.proto` 之后 `git status --short` 为空。
- 两个 Go 模块 `GOWORK=off go build ./... && go vet ./... && go test ./...` 通过。
- 在仓库之外用 `servicehttp.Parse` 解析三份 JSON 成功，路由条数是 36、55、1。
- 和 `tech/09` 第 3.3、4.1 节逐条对上，没有漏、没有多。

## WS0b 服务骨架

WS0a 合入后，直接在 `main` 的主检出里做。它给后面三个后端工作流定边界，所以除了骨架，还要把所有工作流共用的东西一次做掉。

拥有：`service-mail/`（除下面标给 WS1 到 WS4 的包之外的全部）、`.github/workflows/ci.yml` 的服务检查部分、`README.md`。

依据：`docs/conventions/backend-service-conventions.md` 全文，其中第 10 节的新服务检查清单要逐条满足。和 service-file 不一致的地方按下面来：

| 事项 | 做法 | 原因 |
|---|---|---|
| 配置 | 放 `internal/config`，照 service-iam 的形状：严格解码、生产门禁、`Summary()` | 目录规范和 O05 的要求；service-file 的检查只验了文件能解析 |
| servicehttp | 用 v0.2.3 | v0.2.1 不认 PATCH 路由，而重命名文件夹用的是 PATCH |
| HTTP 服务 | 用 `httpstarter.New`，带超时 | service-file 没有超时 |
| 健康检查 | `/ping`、`/healthz`、`/metrics` | O03-2、`tech/10` 第 5 节 |
| 日志 | `logx` 带上下文，请求日志带 request_id | 排障需要 |
| 数据库 | 只支持 MySQL。迁移用 golang-migrate 加内嵌 SQL，第一个版本就是 `ppb-docs/mail/tech/sql/schema.sql` | `ADR-005` 第 3 节 |
| 依赖契约 | 仓库没有远端，`go.mod` 里先用本地 `replace` 指向 `../contracts-mail` 和 `../contracts-mail/kitexstubs`，写明发布后要改成版本号 | 平台惯例是不用 replace，但那要求先发 tag |
| 雪花节点 | 先核对各服务用了哪些节点，再选一个没被占用的（文档里给邮件留的是 3） | 节点不能撞 |
| 密码、令牌 | 不进日志、不进 `Summary()`、不进错误信息 | X06 |

任务（按顺序）：

1. `go.mod`：模块路径 `github.com/maibanku/ppb-mail/service-mail`，Go 1.26。把后面工作流会用的第三方库一次加齐（IMAP 客户端、MIME 解析、HTML 净化、Argon2、DNS 解析），之后别人尽量不再动 `go.mod`。
2. `internal/config`：配置结构（键名见 `tech/10` 第 4.1 节）、加载、环境变量覆盖、校验（含 `tech/10` 第 4.3 节的检查项和生产门禁）、`Summary()`。测试：正控一条，每一类负控各一条，`Summary()` 里没有任何秘密。
3. `cmd/server/main.go`：`-config` 和 `-check-config`。`-check-config` 通过退出 0，失败退出非零，不连库、不迁移、不监听、不生成密钥。测试钉住退出码。
4. `cmd/server/boot_wire.go`：装配顺序照约定（配置、日志、检查出口、开库、迁移、结构校验、出站客户端、组件、启动、反向停止）。
5. 装配接缝：每个后端工作流一个文件、一个构造函数。`wire_admin.go`（WS1）、`wire_mailbox.go`（WS2）、`wire_ops.go`（WS3）、`wire_render.go`（WS4 的后续）。先放能编译的空实现，函数签名一次定好。
6. HTTP 骨架：`/ping`、`/healthz`（依次确认数据库、IMAP 主账号登录探测、策略端口）、`/metrics`。成员面和管理面的路由挂载点各一个聚合文件，按组预留给后面的工作流填写。
7. `internal/platform/db`（开库、探活）、`internal/platform/idgen`（雪花发号）。
8. `internal/dbmigrate`：迁移脚本、启动时执行、`cmd/migrate` 独立入口、结构校验。测试：在一次性 MySQL 容器上空库可执行、可回滚；没有容器时跳过并说明。
9. 全部表的模型：24 张表，放在各自所属包的 `model` 子包里，列名显式写，状态取值用常量。`deriveStatus`（邮箱状态推导，见 `tech/08` 5.3）配真值表测试。物理删除的表不带软删过滤。
10. `internal/mailconf`：全局设置的类型化登记（键、默认值、范围见 `tech/07` 第 11 节）、读写、越界拒绝。
11. `internal/mailaudit`：审计写入、动作码常量、操作者类型。
12. `internal/mailerr`：`tech/09` 第 6 节的全部错误码。测试：格式、编号不重复、不占用 9001 和 9002。
13. `api/contracts.go` 和测试：用 `servicehttp.Parse` 解析三份契约。
14. `env/mail-dev.yaml`、`env/mail-prod.template.yaml`。
15. CI 的服务检查、`README.md`（怎么构建、测试、起本地环境）。
16. 给 WS1 到 WS4 的占位包：每个包一个带说明的空文件，说明这个包该做什么、读哪份设计。
17. `service-mail/docs/implementation/wiring-plan.md`：包的归属表、每个接缝函数的签名和它要返回什么、工作流之间用哪些接口对接（接口定义在用的一方）。

完成标准：

- `GOWORK=off go build ./... && go vet ./... && go test ./...` 通过。
- `-check-config` 的正控和负控有测试。
- 迁移在真实 MySQL 上跑通；`bash ppb-docs/mail/tech/sql/verify/run.sh` 仍然通过。
- `wiring-plan.md` 能让后面的人不看别人的代码就知道自己该实现什么。

## WS1 后端·账号与域名

拥有：`service-mail/internal/maildomain/`、`mailaccount/`、`blocklist/`，`transport/mail/manage/` 里域名、邮箱、别名、转发、黑白名单、全局设置、审计这几组处理器，`cmd/server/wire_admin.go`。

依据：`tech/04`（账号与认证）、`tech/07`（管理端设计，第 5 到 12 节）、`tech/08`（数据模型，特别是 5、6、9 节）、`tech/09` 第 4 节；规则 `pr/04-邮箱账号.md`、`pr/03` 的 FP-D01 到 D06、FP-S08、`pr/06-管理端.md` 的 FP-G01 到 G07、G14 到 G16。

任务：

1. 邮箱账号：开通（地址规则 M06、保留字、域行加锁的地址分配）、密码（Argon2id 哈希、临时密码过期、历史三次）、状态操作（停用、恢复、转待删除、彻底删除）、配额、外发权限、修改主地址、别名、域保留地址、转发记录的增删改查、列表（筛选、排序、分页）和汇总。
2. 域名：增删改查、默认域规则、DKIM 密钥生成和轮换、私钥落盘（0400）、主机名登记的启动写入和变更检测、六项 DNS 检查、证书剩余天数。
3. 黑白名单：批量添加、逐项校验、和另一张名单的重复检查。
4. 管理接口：上面各项的 39 个操作，加全局设置和审计列表。操作者身份来自平台的管理登录态，每个请求向 IAM 复检对应权限；写操作按 `tech/07` 第 12 节记审计。
5. 批量任务：`mail_admin_batch`，后台执行、进度回写、逐个记审计、遗留任务标中断。
6. 接缝 `wire_admin.go`。

完成标准：每个包都有测试；地址并发分配只成功一个；审计写失败则操作失败；管理接口的权限复检有负控；`go test ./...` 通过。

## WS2 后端·成员邮箱

拥有：`service-mail/internal/mailbox/`、`mailsetting/`、`mailnotify/`、`platform/imap/`、`platform/smtpsubmit/`，`transport/mail/member/`，`cmd/server/wire_mailbox.go`。

依据：`tech/06`（成员接口设计，全文）；`tech/09` 第 2、3 节和 `contracts-mail/api/streaming-routes.md`；规则 `pr/05-成员接口.md`、`pr/03` 的 FP-S14 到 S18。

任务：

1. IMAP 访问层：隐式 TLS 加证书校验、主账号登录、每人 4 个连接、只读打开、不标已读地取正文、超时。测试用 go-imap 自带的服务器包起一个内存服务器。
2. 带签名的邮件、文件夹、附件标识；解析时校验签名并绑定账号。
3. MIME：解析（中文标题和文件名、字符集转 UTF-8、内嵌图片、密送规则）、HTML 净化（配一组攻击样例）、组装（四种模式、回复关联头、附件文件名编码）。
4. 读：概览、文件夹、列表、搜索、读邮件、会话视图、投递状态；三个流式下载。
5. 写：发送（校验顺序见 `tech/06` 6.2，幂等，限额检查，提交，写已发送副本）、草稿、标记、移动、复制、进已删除、恢复、彻底删除、暂存附件上传。
6. 设置：自动回复、转发（含确认信和匿名确认接口）、过滤规则；渲染成 Sieve 脚本，原子写入，编译不过就回滚。
7. 自助：改密码、设置初始密码、改主地址一次、别名增删。
8. 限速和请求体上限。
9. 成员接口全部处理器和身份映射（成员标识换用户标识，带缓存）。
10. 接缝 `wire_mailbox.go`。

完成标准：跨账号访问一律 404；同一个幂等键并发只发一封；Sieve 转义和渲染有测试；净化样例全部被处理；`go test ./...` 通过。

## WS3 后端·投递与运维

拥有：`service-mail/internal/outbound/`、`delivery/`、`mailqueue/`、`accountsync/`、`mailstatus/`，`transport/postfixpolicy/`，`platform/mailops/`、`platform/rspamd/`，`transport/mail/manage/` 里限额、队列、日志、状态这几组处理器，`cmd/server/wire_ops.go`。

依据：`tech/07` 全文（运维代理、出站限额、后台任务、日志采集、队列、系统状态）；`tech/10` 第 11、12 节（指标、告警、日志）；`tech/04` 第 2 节（对账）；`ppb-mail/docs/mailops-protocol.md`；`ppb-mail/deploy/docs/log-samples.md`（WS4 产出，拿得到就用，拿不到先按 `tech/07` 第 5 节写并标注待对）。

任务：

1. mailops 客户端和测试（假套接字服务器）。
2. 出站限额：计数器、覆盖值、Postfix 策略协议服务（只处理 RCPT 阶段、三种回复、超时、放行）。
3. 日志采集：文件tail、断点、轮转、去重；Postfix 和 Dovecot 的解析器（表驱动测试）；最近登录回写；Rspamd 历史记录轮询；保留期清理。
4. 队列操作经 mailops；入站方向的队列项拒绝重发和删除。
5. 账号对账：期望集合、现有集合、差异和动作、执行记录。IAM 的「列出全部用户」内部接口现在没有，用接口隔开并在装配说明里写清楚。
6. 状态采集和缓存。
7. 后台任务登记表（`tech/07` 第 4 节）、告警评估和通知。
8. 指标。
9. 管理接口的 15 个操作和投递日志导出。
10. 接缝 `wire_ops.go`。

完成标准：解析器对每类样例行有测试；断点重启后不重复不遗漏；策略服务不可达时放行；告警去重和恢复有测试；`go test ./...` 通过。

## WS5 成员网页客户端

拥有：`ui/`。

依据：`ppb-mail/docs/design/README.md` 和 `screens/`；`docs/conventions/frontend-conventions.md`（第 2、3、6、7 节）；`tech/09` 第 2、3 节和 `contracts-mail/api/`（契约 JSON 是字段的事实来源）；`pr/05-成员接口.md`。

技术栈按约定指南第 7 节：Vue 3、TypeScript、vue-router、Vite，模块级 reactive 单例，自己封装 fetch，不引组件库，图标用 lucide，普通 CSS 加 `--mail-*` 令牌，vitest 加 jsdom。

登录用 OIDC 授权码加 PKCE，回调落到应用自己的路由。协议件参照 `ppb-chat/chat-desktop/src/auth/iam.ts` 改写成浏览器版。访问令牌放内存，刷新令牌放 sessionStorage。客户端登记、跨源白名单、托管路径是部署时要配的，写进 README 的部署前提。

任务：

1. 脚手架、令牌、基础样式、路由、应用外壳（侧栏、顶栏、三栏）。
2. 登录、会话、静默续期、登出（只清本地）；「没有邮箱」状态页。
3. HTTP 封装：信封解析、错误对象带 code、status、data；`Idempotency-Key`；`Retry-After`；流式下载转 Blob。
4. 开发和测试用的模拟接口层：按契约 JSON 实现一套内存数据，覆盖全部成员操作。
5. 设计稿的 16 屏，按设计说明逐屏做；设计稿没画的（下拉、确认框、加载和出错状态、轻提示）按同一套规则补。
6. 测试：纯函数、状态、关键组件和页面各一组。

完成标准：`npm run typecheck`、`npm test`、`npm run build` 在 Node 24 下通过；16 屏都有对应路由和页面；身份一律写成「昵称(邮箱地址)」；README 写清怎么起开发环境、部署前提和与设计稿的差异。

## WS6 管理端插件

拥有：`mail-manage-web/`。

依据：`docs/conventions/frontend-conventions.md` 第 3、4、5、6 节；模板 `ppb-file/file-manage-web`；`tech/09` 第 4 节；`pr/06-管理端.md`；`tech/07` 第 13 节的页面表。

任务：照 file 插件建工程（开发端口 8274，8270 已被衣橱后端占用）；插件清单、路由和权限声明；接口模块；13 个页面（域名、邮箱、别名、转发、黑白名单、出站限额、队列、投递日志、登录日志、评分记录、系统状态、全局设置、审计记录）；危险操作的确认框；页面测试。

完成标准：类型检查、测试、`build:lib` 通过；没有对应权限的菜单项不显示；列表都用底座的表格组件。

## WS8 平台接入

在 ppb-gateway 和 ppb-base 各开一个分支做，不碰 main，不推送。

ppb-gateway：

1. 流式直转车道：`/api/v1/mail/` 整段走透明直转到 mail 上游；`/api/v1/manage/mail/logs/delivery/export` 单独一条。契约里的精确路由优先级更高，不受影响。
2. 让 `gateway.yaml` 里每个上游的 `timeout_ms` 真正生效。现在配置写的是 `upstreams`、代码读的是 `upstream`，整段被忽略，所有上游共用 3 秒。mail 上游要 120 秒；其他上游的行为不变。
3. 测试。

ppb-iam：

1. 业务桥（`service-iam/internal/bridge/bridge.go`）加 `/api/v1/manage/mail/` 的前转，目标地址由配置给出；补测试。现在除 file、camera 两个前缀外一律转给 IM。

ppb-base：

1. `deploy/route-manifest.yaml` 加 mail 上游和服务条目，停用的旧条目改掉；重新生成路由表。
2. 策略清单聚合脚本认识 `../ppb-mail/api/policies`。
3. `start-all.sh` 和 `stop-all.sh`：构建并启动 service-mail，带 `-check-config` 门禁。
4. `platform-manage-web` 注册邮件插件（三处改动照 file 的先例）。
5. 删除 `deploy/config/mail.yaml` 这个指向不存在模块的旧文件。

完成标准：生成路由表的命令跑通且结果提交；网关的测试通过；改动只在分支上。

## WS9 集成

1. 把 WS1 到 WS6、WS8 的分支合进 `main`，解决冲突（主要会在 `go.mod`、`go.sum` 和装配文件上）。
2. 全量检查：三个 Go 模块、两个前端工程。
3. WS4 的后续：在 service-mail 里实现按模板渲染 Postfix、Dovecot、Rspamd 配置的包，接到 `wire_render.go`。
4. 本机联调：起邮件核心编排和 service-mail，走通「管理接口开通邮箱、标准客户端收发、HTTP 接口读到同一封邮件」。
5. 对照 `ppb-docs/mail/ac/02-邮箱系统验收标准.md` 填能填的条目，证据放 `ppb-docs/mail/ac/evidence/M2/`。
6. 另起一个 agent 做整仓评审，按上面的「评审时重点看」五条逐条查；严重的修掉。
