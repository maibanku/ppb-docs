# 通知邮件缺口修复 实施进度

> 工作区文件，不提交。分支 `fix/notify-mail-gaps`（ppb-iam worktree，基线 main@86f19e8；
> ppb-chat worktree 基线 main@bb805601）。设计：`ppb-docs/mail/tech/11-通知邮件缺口修复设计.md`（v0.2）。

环境：Go 1.26.0（`/Users/pipi-ban/sdk/go1.26.0/bin`，与 `service-iam/go.mod` 的 `go 1.26.0` 一致）；
`GOWORK=off GOPRIVATE=github.com/maibanku/*,github.com/ppbchat/*`。

测试命令缩写：

- **全量** = `cd service-iam && GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test ./... -count=1`
- **包** = `GOWORK=off go test <包路径> -count=1`

## 0. 基线（改动前）

全量：20 包 ok / 0 FAIL（17 个包无测试文件）。`contracts-iam`：`GOWORK=off go build ./... && go test ./...` 通过。

## 1. 设计第 15 节核对结论

| 核对项 | 结论 |
|---|---|
| Go 版本 / go.work / GOPRIVATE | `go 1.26.0`，本机同版本。仓内无 go.work，README 与 CI 均 `GOWORK=off`（防兄弟仓 go.work 串扰）。CI 的 env 是 `GOPRIVATE=github.com/maibanku/*,github.com/ppbchat/*`。README 里「server-pkg 经 replace 桥接 ppb-base」一段已过时（go.mod 现无任何 replace）。 |
| proto 生成命令与产物范围 | 在 `contracts-iam/` 下：`buf generate --path proto/iam.proto --path proto/iamx.proto --path proto/admincompat.proto --path proto/manage.proto`（buf.gen.yaml 头注）。产物只有 `gen/go/iam/*.pb.go`。生成器钉 protoc-gen-go v1.34.2 / protoc-gen-go-grpc v1.5.1，本机已装同版本，buf 1.74.0 与 CI 一致。`kitexstubs/iam/*.pb.go` 不由 buf 生成：是手写的类型别名层（指向根模块 `gen/go/iam`），服务组是 Kitex v0.16.3 生成件。给既有消息加字段只需重生成根模块，别名层不用动。 |
| **契约模块怎么被服务看到** | `service-iam/go.mod` 里 `contracts-iam v0.3.1`、`kitexstubs v0.3.2` 是远端 tag，**没有 replace**。仓库既有流程是「改 proto 并重新生成 → 打 tag 推送 → service 抬版本」（见 `contracts-iam/v0.3.1` 与提交 1d2533b）。本任务不许推送，worktree 里重新生成的代码服务看不到，`servicehttp.Parse` 会因描述符里没有新字段而拒绝契约绑定。处理：按仓库注释里的既有做法加**发布前本地 replace 桥** `replace github.com/maibanku/ppb-iam/contracts-iam => ../contracts-iam`（`7c33fe7` 收编批收口前就是这种桥；tag 发布后改 require 新版本并撤掉此行）。v0.3.1 tag 的 `gen/go` 与 HEAD 逐字节一致，桥接不引入无关漂移。 |
| 迁移测试写法 / 新脚本是否要登记 | 迁移是**双轨**：MySQL 走 golang-migrate（`migrations/*.sql` 经 `//go:embed` 嵌入，无需登记，文件名即版本）；SQLite 走 GORM AutoMigrate（`migrate.go` 的 `migrateOrder`），**完全不读 .sql 文件**。所以设计第 4.4 / 7 节和任务说明里「迁移测试把全部脚本在 SQLite 上跑一遍」不成立：`TestMigrateMemorySQLite` 只跑 AutoMigrate。见下文 F2 / F5 的处理。 |
| 平台指标模块 | `go-framework/obs`：`obs.Default` 注册表；`Counter(name, help, labels...)`、`Histogram(name, help, buckets, labels...)`、`FuncGauge(name, help, fn)`。**没有带标签的 gauge，也没有可写值的 gauge**；没有读值 API，测试只能经 `Handler()` 的 Prometheus 文本输出读；没有复位 API（计数跨用例累加，断言要读前后差值）。全平台各服务只挂 `obs.Default.Handler()`，没有自定义业务指标先例。 |
| 配置 prod 用例准备方式 | `config_test.go`：`prodBase()` 取 `DefaultConfig()` 后改 MySQL DSN / https issuer / 非默认凭据，`t.Setenv(EnvAppEnv, "prod")` 后直接调 `validate()`。 |
| chat-manage-web 页面测试写法 | `AuditView.test.ts`：`vi.hoisted` 造 mock + `vi.mock` 掉 API 模块；mount 真实 `ProTable`（`ElementPlus` + `ElTag` 桩插件）；`setProfile` / `clearProfile` 配权限；`flushPromises`。 |

## 2. 逐项记录

（每完成一项追加一行：提交号、测试命令、结果、遗留）

### 1. F1 SMTP 投递加总时长上限 — `cd293c7`

- 红：`包 ./internal/platform/smtp -run Stalled` 先是编译失败（`smtpDeliveryTimeout` / `notify.ErrDeliveryTimeout` 未定义）；只补这两个声明后再跑，两例各在 3 秒后以「投递没有在时限内返回」失败——即现状的挂起。
- 绿：包测试全过（两个超时用例 0.20s）；`-race -count=3`、`-run 'Stalled|RoundTrip|ServerReject' -count=30` 通过。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 判断 1：设计 3.2 是「连接建立后」才设截止时间；规则 04-1 要求连接阶段也受总时长约束，所以截止时间在拨号前定一次，拨号带同一截止时间的 ctx。最坏耗时从「系统连接超时 + 5 秒」变成 5 秒以内。
- 判断 2：「EHLO 失败回退 HELO」的中继，`SendMail` 会跳过认证继续投递；自写会话按「未宣告 AUTH」失败（`Client` 扩展表未导出，分不出这两种情况）。生产中继不受影响。
- 遗留：STARTTLS 升级路径没有自动化覆盖（改动前在标准库内部，同样没有；现在逐行对照 `SendMail`）。拨号挂起没有用例（设计未列，本机造不出稳定的假服务器）。

### 2. F6 验证码生成改为无偏采样 — `e77fa4f`

- 红：`包 ./internal/account/service -run 'CodeFromUint32|GenCode'` 编译失败（`codeFromUint32` / `codeSpace` 未定义）。纯函数新加，红只有这一层。
- 绿：`TestCodeFromUint32_Bounds`、`TestCodeFromUint32_AllDigitsReachable`、`TestGenCode` 通过；常量 `codeRejectionLimit` 实测 4294000000。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 与设计不符：设计把 `TestGenCode` 写成「现有用例」，仓库里没有，按设计断言新建。

### 3. F3 验证码邮件模板单一来源 — `da1c826`

- 红：`TestRenderCodeMail_Purposes` 编译失败（`RenderCodeMail` 未定义）；`TestLogSendCodeSenderMatchesWire`（先用现有两参构造）行为失败：记录主题「【ppbChat】邮箱验证码」≠ 实发「【PPB】注册验证码」。
- 绿：`包 ./internal/notify ./internal/platform/smtp` 全过（含现有 `TestBuildCodeMessage`、`TestLogSendCodeSenderRecords`）。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 判断 1：设计 5.2 的自述接口叫 `ChannelReporter`（含 `Channel` 和 `FromAddress`）。按第 13 节顺序 F3 排在 F2 前面，`Channel` 此时还不存在，所以本提交先引入只有 `FromAddress` 的 `DeliveryReporter`，F2 提交再扩成 `ChannelReporter`，最终名字与设计一致。
- 判断 2：设计没说记录器从哪拿有效期。`NewLogSendCodeSender` 多一个 `codeTTL` 参数，装配处传 `account.ChallengeTTL`（有效期属于账号域，notify 不能反向依赖）。
- 测试细节：实发正文在线路上是 CRLF 行尾且末尾多一个行结束符（标准库 DATA 写入端统一行尾），模板文本是 LF 行尾；`MatchesWire` 比较前把线路形态归一，其余逐字比对。
- 未改的现状：未知用途拼出「【PPB】验证码验证码」/「您的验证码验证码：…」，是现状实发文案，本批不改。

### 4. F2 投递记录标明通道 — `4e81e76`

- 红（分两层）：`TestListEmailSendLogsFilterChannel` / `TestLogSendCodeSenderRecordsChannel` 先编译失败；只加声明不加逻辑后再跑，行为失败（筛选返回 3 行、真投递器记录通道为 0）。`TestEmailSendLogChannelMigrationSQLite`（脚本文件不存在）、`TestUserManageContract_EmailLogDeliveryChannel`（绑定缺失）行为失败。handler 与绑定用例编译失败（链接的还是远端 v0.3.1 契约类型）。
- 绿：`包 ./internal/notify ./internal/platform/smtp ./internal/dbmigrate ./api ./cmd/server ./internal/transport/iam` 全过。handler 用例做了变异核对（不传筛选、响应不带通道都会失败）。
- 提交前全量：service-iam build / vet 通过，20 包 ok / 0 FAIL；`contracts-iam`、`kitexstubs` 构建测试通过；`buf breaking --against 86f19e8` 通过；重新生成幂等（再跑一次 `buf generate` 生成物哈希不变）。
- proto 生成：改基线前先在未改动的基线上跑了一次 `buf generate`，生成物逐字节一致，证明本机工具链（buf 1.74.0 / protoc-gen-go v1.34.2 / protoc-gen-go-grpc 1.5.1）能复现已提交产物。
- 判断 3（契约链接）：加发布前本地 replace 桥。落地时要先推 `contracts-iam` 新 tag，再在 `service-iam/go.mod` 抬版本并删掉 replace 行。
- 判断 4（迁移双轨）：设计与任务说明的前提「迁移测试把脚本在 SQLite 上跑一遍」不成立。脚本写成双方言中性语句；SQLite 的列由 AutoMigrate 建出；另加测试把 000002 在 SQLite 上回退再前滚。
- 判断 5：`VerifySchema` 此前没登记投递记录表。本批登记 `DeliveryChannel` 列（只锁本批引入的列），MySQL 上脚本没生效即拒起；在 SQLite 上删列后 `VerifySchema` 确实报错，有用例。
- 遗留：000002 在 MySQL 上的执行没有自动化（迁移测试不连 MySQL，本任务也不许连本机库）。
- 环境插曲：`go list -m` 在加了 replace 后卡死（栈顶在 `modinfo.(*ModulePublic).String`，0 CPU、无网络），强杀后改用 `go build` 验证，正常。之后没再出现。

### 5. F5 推送记录排序列加索引 — `f041b89`

- 红：在 `VerifySchema` 登记索引后，现有 `TestMigrateMemorySQLite` 报「schema missing … index idx_email_send_log_create_time」——设计要的「现有迁移测试会执行这个脚本」落在这里；新用例 `TestEmailSendLogSortIndexMigrationSQLite` 报索引列为空。
- 绿：`包 ./internal/dbmigrate` 3 个用例全过。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 判断 6：`create_time` 来自嵌入的外部模块 `dombase.BaseModel`，gorm 索引标签打不到嵌入字段上（查了 GORM 1.31.2 的解析逻辑：`ParseIndexes` 只读字段标签，没有 `Indexer` 接口；在模型上遮蔽 `CreateTime` 会让扫描绑到嵌入字段，不可取）。处理：SQLite 路径在 AutoMigrate 之后执行与 MySQL 同一份 000003 脚本（已有索引则跳过），索引名和列序只有脚本一处定义。
- 判断 7：000003 的回滚脚本用 MySQL 写法 `DROP INDEX … ON …`。SQLite 的 `DROP INDEX` 不带 `ON` 子句，两边没有共同写法；脚本只经 golang-migrate 在 MySQL 上执行。
- **没做**：设计第 7 节「在 MySQL 测试库上用 EXPLAIN 确认索引用上了」——没有测试库，任务也不许连本机 3306。替代证据：SQLite 上 `EXPLAIN QUERY PLAN`，有索引时列表排序是 `SCAN … USING INDEX idx_email_send_log_create_time`，无索引时是全表扫描加 `USE TEMP B-TREE FOR ORDER BY`，有用例锁住。MySQL 上的查询计划仍待上线前在测试库确认。

### 6. F8 生产环境拒绝日志投递 — `9c98c79`

- 红：`TestConfig_ProdRejectsDevDeliveryLogOnly` 第一条断言失败（prod 开日志投递，`validate` 返回 nil）。加门禁后，现有 `TestProdGates` 的「合法生产配置应通过」失败——它的基线 `prodBase()` 取自默认配置、带着开关为真；按设计「照现有 prod 用例准备」把它改成开关为 false。
- 绿：`包 ./internal/config` 13 个用例全过。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 真实入口核对：编译服务二进制实际跑 `-check-config` 与正常启动。prod+开：两者都退出码 1，报「不允许日志投递」，不连库；prod+关、dev+开：`config check ok`。
- 判断 8（设计未列，顺带修）：`-check-config` 摘要的 `delivery=` 标签只看 SMTP 主机是否为空，「开关关闭且未配 SMTP」也显示 `log-only`。门禁之后这是生产常态，摘要与事实相反，改为按装配顺序取 `smtp-armed` / `log-only` / `none`；加了 `TestConfigSummary_DeliveryLabel`。
- 升级注意：按旧模板生成的生产配置里这一项是 `true`，升级后服务拒绝启动，要改成 `false` 并配齐 SMTP 四项与口令。

### 7. F7 推送记录保留期与每日清理 — `e199dbc`

- 红：`TestDeleteEmailSendLogsBefore` / `TestConfig_EmailLogRetentionDays` / `TestEmailLogCleanup_RunsAfterDelayAndStopsOnCancel` / `TestBuildComponents_EmailLogCleanupWiring` 均编译失败（函数、字段、组件不存在）。接上装配后现有 `TestBootShutdownOrderReverse` 转红：停机次序实际为 `[http grpc email-log-cleanup]`。
- 绿：`包 ./internal/notify ./internal/config ./cmd/server` 全过；`cmd/server -race -count=3`（清理用例）、`notify -race` 通过。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 判断 9：清理组件排在 RPC / HTTP 入口之前（boot 约定：依赖 → worker → 入口），最后停。现有停机次序用例的预期从 `[http, grpc]` 扩成 `[http, grpc, email-log-cleanup]`，「HTTP 先于 gRPC」不变。
- 判断 10：清理出错只记日志、不返回错误——`boot` 把组件返回错误当作运行期故障，会整体停机；保留期清理失败不该让服务下线。
- 设计没写的两处自行补定：保留天数在装配处换算成保留期（天数 × 24 小时）；分批删除按主键翻页（不用 `DELETE … LIMIT`，MySQL 与 SQLite 支持不一；也不拼超长 IN 列表）。

### 8. F13 投递指标 — `7b8db02`

- 红：`TestLogSendCodeSenderRecordsDeliveryMetrics` 行为失败（`iam_email_delivery_total{purpose="register",result="success"} 增加 0，期望 1`）。
- 绿：`包 ./internal/notify ./cmd/server` 全过。
- 提交前全量：build / vet 通过，20 包 ok / 0 FAIL。
- 判断 11（通道度量的形状）：设计是带 `channel` 标签的 gauge、当前通道一条值为 1 的序列。平台 `obs` 只有不带标签的采样型 `FuncGauge`，做不出带标签的序列，框架又不能改；要标签形状只能在本服务另起一条指标输出路径。按「最小改动满足规则」，通道以编号体现在度量值上（0 未知或未装配 / 1 SMTP 真投递 / 2 日志投递）。指标名沿用设计的 `iam_` 前缀（平台自带指标是 `ppb_` 前缀）。
- 读值方式：`obs` 没有读值接口和复位接口，用例经 `Handler()` 的文本输出读前后差值。通道度量懒注册（装配记录器时才出现）。
- 竞态检测（CI 不带 `-race`，属额外核对）：本批改过的包在 `-race` 下全过。`cmd/server` 有两个用例在 `-race` 下会间歇报数据竞争——`TestKitexIMOutboundHeaderChain`（测试自己没同步的字段）和 `TestBootStartupPortConflictFailFast`（Kitex 启动与停机并发）——在基线 `86f19e8` 上同样复现（分别 5 次中 3 次、20 次中 1 次），既有问题，本批没修；跳过这两个后 `cmd/server -race` 通过。

### 9. F4 管理页的类型筛选和通道展示 — ppb-chat `0bec93b5`

- 位置：`/Users/pipi-ban/Desktop/code/vscode/ppb-chat-ws/notify-mail-gaps`，分支 `fix/notify-mail-gaps`，`chat-manage-web/`。
- 环境：worktree 在 `ppb-chat-ws/` 下比主检出深两层，`chat-manage-web` 被跟踪的源码、`package.json`、`vite.config.ts`、`tsconfig.json` 里的 `../../ppb-base/base-manage-web` 相对引用全部落空。不改被跟踪文件只有一种解法：建软链 `ppb-chat-ws/ppb-base -> ../ppb-base`（**在 worktree 之外**，为跑通检查而建，未删除）。随后在 worktree 内 `npm ci`（Node 24.21.0）。
- 基线：`npm run typecheck` 通过；`npx vitest run` 18 个文件 90 个用例通过。
- 红：`npx vitest run src/views/ops/EmailLogsView.test.ts` 三条按设计列出的原因失败——类型列显示 `reset_password_code` 等原始代码、下拉只有「验证码」一项、没有通道列。
- 绿：4 条通过（设计的三条 + 补的一条「通道筛选带参」）。变异核对：「通道不传给接口」「状态列不区分日志投递」两种改法都会让对应用例失败。
- 提交前：`npm run typecheck` 通过；`npx vitest run` 19 个文件 94 个用例通过。
- 判断 12：接口零值省略，通道未知时返回项没有 `deliveryChannel` 字段，页面按未知处理；取值不在 0/1/2 范围内的也按未知。通道筛选不提供「未知」项（服务端把 0 当不限，筛不出来）。
- 遗留：设计验收映射里的「页面走查」（AC-21）没做。记录正文现在带一个空行（两段），详情浮层按单行显示，不影响内容，属可选的展示优化。

## 3. 总体结果

| 仓库 | 分支 | 提交 |
|---|---|---|
| ppb-iam | `fix/notify-mail-gaps` @ `7b8db02` | 8 个：`cd293c7` `e77fa4f` `da1c826` `4e81e76` `f041b89` `9c98c79` `e199dbc` `7b8db02` |
| ppb-chat | `fix/notify-mail-gaps` @ `0bec93b5` | 1 个：`0bec93b5` |

- service-iam 最终 HEAD：build / vet 通过；20 包 ok / 0 FAIL；顶层用例 360 通过（子用例 34），0 失败 0 跳过。本批新增后端用例 21 个。
- contracts-iam / kitexstubs：构建测试通过；`buf breaking --against 86f19e8` 通过；最终 HEAD 上重跑 `buf generate` 后 `git diff --exit-code` 为 0。
- chat-manage-web：typecheck 通过；vitest 94 / 94。
- 未推送、未合并；两个主检出停在原提交、工作区干净。

### 没做的

- MySQL 测试库上的迁移执行与 `EXPLAIN`（设计第 7 节）：没有测试库，任务也不许连本机 3306。
- 页面走查（AC-21）。
- 设计第 14 节末尾要求把 `ppb-docs` 里规则条目的状态和验收标准的证据栏更新：任务禁止修改 `ppb-docs`。
- STARTTLS 升级路径没有自动化覆盖（沿用现状）。

### 落地前要做的事

1. 推送 `contracts-iam` 新 tag；在 `service-iam/go.mod` 里把 `require github.com/maibanku/ppb-iam/contracts-iam` 抬到新版本并删除文件末尾的 `replace` 行（随后 `go mod tidy` 清掉 go.sum 里 v0.3.1 的残留）。
2. 在 MySQL 测试库上执行 000002 / 000003 并用 `EXPLAIN` 确认列表查询走 `idx_email_send_log_create_time`。
3. 生产配置：`dev_delivery_log_only` 必须为 `false`，SMTP 四项与口令配齐；按旧模板生成的配置升级后会被拒绝启动。
4. F7 的 180 天、F8 的「拒绝启动」在 `ppb-docs/mail/PRD.md` 第 11 节仍标着待确认。
