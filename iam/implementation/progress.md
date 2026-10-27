# IAM 跨仓实施进度（progress）

> 依据：`iam/implementation/CLAUDE_CODE_PROMPT.md`。本文件每阶段更新：需求编号、改动文件、各仓分支/提交 SHA、实际命令与结果、迁移状态、遗留与下一步。

## 当前状态（2026-10-27，随每阶段刷新）

**执行到**：阶段1 全闭环+本机运行验证——build/vet/test 全绿（§5 验证轮）+ SQLite 联库迁移修复与七进程 start-all 跑通（§5 运行轮，2026-10-27 macOS 会话）；阶段2 未启动。

| 阶段 | 状态 | 产出/证据 |
|---|---|---|
| 阶段0 基线与检查点 | ✅ 完成·已推送 | 四仓起点 SHA 对账吻合 bootstrap 记录；progress/migration-checklist/ADR-008；ppb-docs 至 `aee037f` |
| 阶段1 server-iam 账户/注册登录 | ✅ 完成·已验证 | ppb-base `6a2251e`（20 文件 +1918）+ 修复 `1389270`：骨架/7表模型+`0001_init.sql`/repo 单事务/注册登录服务/mock 单测；build/vet/test 全绿（§5 验证轮） |
| 阶段2 OIDC/门户/后台 | ⬜ 未启动 | 前置：ADR-005 协议库选型（P0）、idl/iam.proto 定稿 |
| 阶段3 平台角色菜单权威替换 | ⬜ 未启动 | platform_* 七表链路（§3.F） |
| 阶段4 chat/camera 接入 | ⬜ 未启动 | 两 chat 客户端 + iOS；跨仓 file 依赖构建 |
| 阶段5 迁移演练与退役判定 | ⬜ 未启动 | switch_check（migration-checklist §3）；server-user 退役条件（迁移计划 P4） |

**后续需要做（按序）**：

1. ~~编译+测试验证~~ ✅ 已闭环（2026-10-27 macOS 会话，见 §5 验证轮；修复提交 ppb-base `1389270`）；go.sum 结论见 §0
2. **ADR-008 四项拍板**（架构决策.md）：#3 邮件域落点 / #4 公告去向 / #5 部门负责人列 / **#6 工号身份类型（最急，影响 user_identities 三列唯一键设计）**；拍板后同步 schema.sql/字段字典/验收
3. ~~补三处登记~~：start-all/stop-all 已完成（`17023d3`，见 §5 运行轮）；剩 gateway upstream（`proxy/grpc_clients.go` + `config/gateway_config.go` + `deploy/config/gateway.yaml`，等 idl/iam.proto 定稿）与 `tools/ci.sh`
4. **阶段2**：idl/iam.proto 定稿（buf 生成，不手改桩）→ handler/网关接线（main.go TODO 位）→ OIDC 授权码+PKCE S256/Discovery/JWKS/刷新轮换 → iam-web / iam-manage-web → DeliverySender 接邮件域
5. **阶段3–5**：platform_* 权威替换与缓存失效重设计（ADR-008 #12）→ chat 组织数据迁 server-im + 两客户端/camera iOS 接入 → 迁移演练、对比报告、server-user 退役判定
6. **环境债**：本实施会话无 shell（git 经有界脚本通道执行，subagent 工具面不稳定）；ppb-docs stash `rollback-before-pull-20261027` 仍在（与分支内容疑似重叠，处置前先对账，勿直接 pop）

## 0. 会话与环境约束（2026-10-27 记录）

- **本会话无 shell**：主会话与 subagent 均无 Bash。commit / push / go build / go test 由用户 `!` 前缀代跑或换有 shell 的会话执行。git 基线经直读 `.git/`（config / refs / logs）重构，非 `git` 命令输出。
- **数据库约束演进**：初版（2026-10-27 早）暂不连真实数据库；同日晚用户指示本机初始化并跑通——已按 SQLite 零依赖态完成联库（见 §5 运行轮）。MySQL 实例执行（G6）仍待；Redis 未接入（阶段2+）。
- 工具链版本：go1.26.0 darwin/arm64（2026-10-27 macOS 会话实测）；node/git 待阶段2 前端时补记。
- go.sum：**本工作区约定为无 per-module go.sum**（八服务均无，校验走 ppb-base 根 `go.work.sum`）；`go mod tidy` 因全工作区 genproto 新旧模块歧义（server-camera 同报错）不可用——工作区级依赖债务，登记待办，不阻塞阶段1。
- ppb-docs 存在遗留 stash：`rollback-before-pull-20261027`（On main: camera/iam docs + wardrobe mods，与 feat/iam-v0.4 内容疑似重叠），**未 pop、不动**。

## 1. 四仓起点基线（分支 feat/iam-v0.4，均已配 origin 跟踪）

| 仓库 | remote | 起点 SHA | 备注 |
|---|---|---|---|
| ppb-docs | git@github.com:maibanku/ppb-docs.git | `439ffa4ae8e0772523d9e7187bffca31cc50047b` | main 在 2bbd5d0（已同步远端）；本分支自此切出 |
| ppb-base | git@github.com:maibanku/ppb-base.git | `18cd1c9be4331beee4836667066c295a09185e29` | |
| ppb-chat | git@github.com:maibanku/ppb-chat.git | `36bfa76dc9cc495e040c814a1c1d45b1127cbf66` | |
| ppb-camera | git@github.com:maibanku/ppb-camera.git | `1c88afb3deb754f80f4b3489471722e47e16973b` | |

工作区是否干净：无法确认（无 shell，index 为二进制）；首次代跑 git 时先 `git status` 核对，若四仓有用户未提交改动，按提示词 §1 保留原样并上报。

## 2. ppb-base 工程落点结论（阶段0 测绘）

- **形态**：每服务一个 Go module（`github.com/ppbchat/server-*`），根 `go.work` 汇总，无根 go.mod。`server-iam` = 新顶层目录 + 独立 go.mod + go.work 登记；**以 server-camera（ppb_camera 独立库）为同构模板**。
- **雪花节点号**：user=1 im=2 mail=3 file=4 plugin=5 camera=6（见 `server-camera/internal/domain/base.go:15`）→ **iam=7**。
- **基建薄壳模式**：`server-pkg/dombase`（BaseModel 四柱公共列、NewHooks 发号、NewBizKey 前缀）；各服务 domain 包只做差异薄壳；业务键前缀 iam 侧拟定 `acct_ / iden_ / cred_ / app_`（以 tech/字段字典为准，待 §3 确认）。
- **DB 访问**：GORM；建连走 `server-pkg/database/db_connect.go`（MySQL/SQLite 双驱动）；迁移 = 自研 AutoMigrate + VerifySchema（参照 `server-camera/internal/repo/camera_migrate.go` + `cmd/migrate`），DDL 镜像放 `deploy/sql/ppb_iam/`。与"暂不联库"约束天然兼容。
- **端口**：已占用至 RPC 9106 / HTTP 9116（camera）→ iam 拟用 **9107/9117**。
- **安全契约**：内部 gRPC 走 `server-pkg/internalauth`（`x-ppb-internal-token`，env `PPB_INTERNAL_RPC_TOKEN`，fail-closed）；管理面授权回源 `server-pkg/authzport`。
- **配置/健康/日志**：yaml + env 覆盖（DSN 走 `*_DB_DSN` 模式）；HTTP /ping + `server-pkg/health`；日志 `server-pkg/logx`（zap）。
- **新服务五处登记清单**（iam 落地时逐一补齐）：go.work、`server-gateway` upstream 表（`proxy/grpc_clients.go` + `config/gateway_config.go` + `deploy/config/gateway.yaml`）、`deploy/config/`、`deploy/scripts/start-all.sh`、`tools/ci.sh`。
- **已知陈旧项（不修，仅记录）**：`tools/ci.sh` 引用不存在的 `chat-client/tools/check_style_gates.sh`（自 ppb-chat 迁移残留）；camera 未纳入 ci.sh 与 start-all。
- server-user 现状（迁移源头）：`internal/domain/{user_model,identity_model,rbac_model,menu_model}.go`；bcrypt DefaultCost；JWT HS256 与网关共享 secret + 会话校验 30s 缓存。

## 3. IAM 设计文档摘要（v0.4，已消化）

- **架构**：ppb-base 内新增 server-iam（独立 module、独立 ppb_iam 库），模块化单体，内部模块 account/profile/identity/credential/authentication/federation/oauthserver/session/application/platformauthz/audit（tech/技术大纲.md:7）。server-user 的通用账号/资料/认证/平台授权迁入 iam，P4 达标后退役（tech/迁移计划.md:42）。
- **阶段1 表集**（DDL 见 tech/sql/schema.sql）：`user`(L20)、`user_profile`(L40)、`user_identities`(L61)、`user_credentials`(L85)、`verification_challenges`(L196)、`audit_events`(L712)、`event_outbox`(L737)。OIDC/应用/会话/平台角色表（oauth_clients、auth_sessions、platform_* 等）留阶段2/3。全量 58 表/674 列是目标态。
- **表/列规范**：雪花 BIGINT UNSIGNED 主键（无自增）+ 实体前缀 biz_key；公共四柱列 create_time/update_time/deleted_flag/deleted_time；**列名≥双单词 snake_case**（字段命名调整.md 共 76 处调整）；`user` 表名保留单词；身份精确列 utf8mb4_bin；逻辑外键无物理 FK。
- **注册流程**（tech/注册与登录流程.md:7）：验证码→verification_challenges（限流+单次消费）→**同库事务**建 user+user_identities+user_profile→密码入 user_credentials→写 audit_events+event_outbox。自助注册不建 platform_admins。
- **凭证红线**：密码仅不可逆哈希（现库为 bcrypt DefaultCost，对齐）；验证码/cookie/恢复码库中只存摘要；IAM token 不得进旧 HS256 解析器。
- **迁移红线**：旧 user_id/user_biz_key 原值迁入；同邮箱不自动合并；旧管理员须确权映射；旧会话不转 IAM token；密码不长期双向同步；回退不得复活旧凭证（迁移计划.md:29-65）。
- **验收**：ac/00-验收总则 G1–G6；P1 须过 G1/G4+G6 结构项。eval/SQL设计验证记录.md 仅静态/SQLite 解析验证，**MySQL 实际执行未做**（G6 缺口，联库阶段补）。
- **P0 待决（ADR-005）**：协议库选型、SQLite 方言适配、subject 策略、时限数值、撤权 SLA、MFA 恢复、HA 指标——生产开放前必须固定。
- 说明：PRD 将 OIDC 授权码+PKCE（IAM-03）列为 P1；本实施按 CLAUDE_CODE_PROMPT 阶段划分执行，OIDC 端点落阶段2。

## 4. 第一条纵向实现路线（阶段1 · 无联库版）

1. `ppb-base/server-iam` 骨架：go.mod（module `github.com/ppbchat/server-iam`，replace server-pkg）+ `cmd/{server,migrate}` + `internal/{domain,repo,service,handler}` + `config.yaml` + /ping 健康检查 + 配置 fail-fast（沿用 PPB_ALLOW_DEV_JWT 类门禁）。go.work 登记。
2. 阶段1 范围表（7 张，见 §3）：user / user_profile / user_identities / user_credentials / verification_challenges / audit_events / event_outbox → domain 模型（dombase 薄壳、雪花7号、双单词列名、biz_key 前缀以 tech/字段字典为准）+ `deploy/sql/ppb_iam/0001_init.sql`（从 tech/sql/schema.sql 原文抽取，标注来源与目标态说明）。
3. 注册 / 登录 service（bcrypt、同库事务、幂等、防枚举）+ handler（gRPC 对齐 idl 惯例；HTTP 仅 /ping）。
4. 单元测试：无 DB —— repo 接口 mock，service 层覆盖注册并发/身份冲突/改密负例。
5. 迁移清单：server-user 表 → iam 表对照 + switch_check 项（写文档，不执行）。
6. 提交粒度对齐提示词示例 1→3；每次提交前跑 build/vet/test（无 shell → 由用户代跑，命令随代码一并提供）。

## 5. 阶段记录

### 阶段0（基线与检查点）——✅ 完成
- 四仓基线：✅（§1）；与 implementation/执行状态.md:24 记录的代码仓起点 SHA 完全吻合（bootstrap.py 已完成四仓建分支职责，此前无 IAM 代码提交）
- 工程测绘：✅（§2）；设计文档摘要：✅（§3）
- **检查点提交：`24e3d89`（chore(iam): establish implementation baseline and migration checklist，ppb-docs，2 文件 +235）**

### 阶段1（server-iam 骨架 → 账户/凭证/注册登录）——✅ 代码已提交，验证已过
- **代码提交：`6a2251e`（feat(iam): add account models, registration and credential verification，ppb-base，20 文件 +1918，含 go.work/deploy 登记与部署模板）**；文档提交：`39d9ace`（ADR-008）。提交前经只读对账：改动清单与预期完全一致、无外来内容，ppb-chat/camera 工作区干净、stash 未动。
- 第1步 骨架 ✅：ppb-base 新增 `server-iam\{go.mod, internal/domain/base.go(雪花7号), internal/service/iam_config.go, internal/repo/iam_db_connect.go, internal/handler/health_ping_handler.go, cmd/server/main.go, cmd/migrate/main.go, config.yaml}`；go.work 已登记（server-gateway 与 server-im 之间）。
  - 有意偏差：Migrate/VerifySchema 并入 iam_db_connect.go（camera 拆独立文件）；拦截链 internalauth（对齐 server-im）；新增 internal_token 配置注入 env；开发门禁 `PPB_ALLOW_DEV_INTERNAL_TOKEN`；main 增优雅退出。
  - 风险/待办：**go.sum 未生成**（无 shell，需 `go mod tidy`）；server-pkg/health 包文件名未定位（用法逐字同 camera，签名可信）；写入时两处 CJK 乱码已修复并复核。
  - 待用户代跑：`cd D:/code/ppb-base && go work sync && go build ./server-iam/...`
- 第2步 表模型+DDL ✅（模型 agent 工具面缺失后由主会话接管完成）：
  - `deploy\sql\ppb_iam\0001_init.sql`：7 表逐字抽取自 schema.sql（user/user_profile/user_identities/user_credentials/verification_challenges/audit_events/event_outbox），头注标明来源行号与"MySQL 未实际执行"缺口。
  - `internal\domain\{user_model,identity_model,audit_model}.go`：GORM 模型，索引显式命名对齐归档 DDL（uk_*）；BINARY(32) 摘要列起步态 `type:blob`（MySQL 以归档 DDL 为准）；CHECK 约束归档 DDL 承载；含 create_time 复合索引（audit idx_actor_key_created_at/idx_created_at）起步态仅建单列、名对齐（GORM 嵌入列限制，代码注释说明）。
  - `base.go` 前缀常量扩充 8 个（acct_/prof_/iden_/cred_/chal_/aud_/obx_/app_），注明"存量 biz_key 原值迁入不重写"红线；`iam_db_connect.go` migrateOrder（7 表先父后子）+ schemaChecks（列+索引名）已接线。
  - 待验证：go build/vet（随第1步命令一并跑）。

- 第5步 迁移对照清单 ✅（agent 交付）：`iam/implementation/migration-checklist.md`（132 行）——server-user 全部 28 张表去向总表、阶段1 列级映射（含双单词改名/类型变化/user_id 原值落点）、switch_check 8 项、未决项 10 条。
  - **发现 12 处代码↔文档不一致**（详见 checklist §4/差异清单）：库名口径（代码为 ppb_user 非 ppb_base）、user_model 包注释过期（7表→实际28表）、邮件域目标无落点（ppb_mail 已移除但迁移计划让迁"邮件域"）、user_announcement 无去向、department.leader_user_id 丢失、employee_code 身份无 identity_type 可落、字段命名调整.md"原字段"是 v0.3→v0.4 稿内映射非存量列、auth_sessions 同名异构、审计结果枚举 success|fail→success/failure、user_status 派生口径差、invitations 三处语义缺口、rbac_revision 无目标表。**均按提示词 §3 处理：不静默改边界，待 ADR 最小修订/用户决策**（阶段2 前集中处理，阶段1 编码不受阻塞）。

- 第3步 注册/登录 service + 单测 ✅（两次 agent 实例均无文件工具，主会话接管）：
  - `internal\repo\account_repo.go`：AccountRepo 接口（服务层只依赖接口）+ GORM 实现；RegisterTx 单事务（挑战 CAS 消费防重放 + 6 行写入 + user 建后回填依赖列）；软删过滤统一 dombase.NotDeleted。
  - `internal\service\account_service.go`：发码（HMAC-SHA256 摘要、明文码不落库、同目标 3 次/时限流、DevDeliveryLogOnly 日志投递）；注册（挑战校验/消费同事务、bcrypt DefaultCost、身份预查+DB 唯一键兜底、防枚举哨兵、audit+outbox 事件 iam.user.registered）；sentinel 错误组。数值时限标注 ADR-005 P0 待决。
  - `internal\service\auth_service.go`：Authenticate（邮箱+密码）：未注册/停用/软删/吊销/密码错统一 ErrInvalidCredentials + dummy bcrypt 拉平时耗；连错 5 锁 10 分钟（对齐旧口径）；成功清零+TouchLastLogin+审计；不发令牌（阶段2 OIDC）。
  - 单测 3 文件（手写 mock 仓储，无 DB、无第三方库）：注册成功行集/挑战消费/确权、错码计次、过期、限流、身份已存在、弱密码、规范化/HMAC 纯函数；登录成功/计数锁定/锁内拒绝/成功清零/四种拒绝态同哨兵/未注册与密码错同哨兵。
  - go.mod 增加 golang.org/x/crypto v0.57.0（版本对齐 server-user）；iam_config.go 增 CodeHMACSecret（env IAM_CODE_HMAC_SECRET + 开发门禁 PPB_ALLOW_DEV_CODE_SECRET）与 DevDeliveryLogOnly。
  - **未做**（如实）：gRPC handler/idl（idl/iam.proto 阶段2 定）；DeliverySender 真实投递（阶段2 邮件域）；main.go 未接 service 构造（无 RPC 入口可挂，留待 idl 定稿）。
  - 待验证：`go mod tidy && gofmt -w && go build && go vet && go test ./internal/service/`（用户代跑）。
- 第4步（收尾调整，用户指示先不编译）✅：cmd/server TODO 注释更新为"服务层就绪、待 idl 接线"；新增 `deploy/config/iam.yaml` 部署模板（internal_token/code_hmac_secret/db_dsn 三空值生产必填、fail-fast 拒起）；**ADR-008** 追加至 ppb-docs/iam/adr/架构决策.md——12 处存量差异登记（4 项文档修订待办、4 项已入 checklist、4 项待用户拍板）。

- 审查轮（2026-10-27，编译前）✅：两个只读 reviewer agent 实例均无文件工具，主会话自查完成。
  - **修复 3 处**：① identity_model.go UserIdentity.UserID 移除复合唯一索引 priority:4（原会把 DDL 三列唯一键建成四列）；② iam_config.go code_hmac_secret 空值拒起（原只拦开发默认值，空 HMAC 密钥可上线）；③ config.yaml 补新键注释。
  - **验证通过**：server-pkg 引用全数核对（obs/recovery/requestid/health 经 camera main 同款用法印证；internalauth/database 直读源码比对签名）；go.work 插行正确（server-pkg 双缩进系存量）；mock 完整实现 AccountRepo 11 方法（`var _ repo.AccountRepo` 编译期约束）；gorm tag/dombase/时间赋值语义自查通过；0001_init.sql 系逐字抽取。
  - **待编译确认（诚实清单）**：gofmt 对齐、go.sum、GORM 运行时行为——无编译器无法验证。
- 验证轮（2026-10-27，macOS 会话，go1.26.0 darwin/arm64）✅：`cd server-iam && gofmt -l -w . && go build ./... && go vet ./... && go test ./...` 全绿（`internal/service ok 2.171s`，其余包无测试文件）。
  - 修复 4 类：① `account_service.go` 7 个结构体字面量删除 `CreateTime/UpdateTime` 赋值（dombase `autoCreateTime/autoUpdateTime` 承担；提升字段不可在字面量赋值，原代码不编译）+ `buildAudit` 的 `now` 变量随之移除；② mock `SaveChallenge` 补时间戳戳章模拟 `autoCreateTime`（限流窗口/最新挑战选择的测试语义依赖 CreateTime）；③ gofmt 补齐 4 文件（实施会话无 shell 遗留）；④ go.sum 确认按工作区约定不生成（§0）。
  - 提交：ppb-base `1389270`（fix(iam): drop promoted base-field literals to close stage-1 build）；tidy 误写 server-camera 的 go.mod/go.sum 已当场还原。
- 运行轮（2026-10-27 晚，macOS 会话，用户指示本机初始化数据库并跑通）✅：
  - **发现并修复 SQLite 全局索引名冲突**：GORM 标签沿用归档 DDL 表内名（`uk_biz_key` 各表重复），MySQL 合法、SQLite 全库唯一——实库首跑即在 user_profile 建索引时失败（mock 单测覆盖不到 DDL 层）。修复：非特定索引名表限定化（`uk_user_biz_key` 等），schemaChecks 同步，新增 `:memory:` 迁移/校验/幂等回归测试（`repo TestMigrateMemorySQLite`）；归档 MySQL DDL 不动，映射差异已注释。提交 `32df5d7`。
  - **deploy 登记**（原五处清单完成 start-all/stop-all 两处）：build `iam`/`migrate-iam`、`IAM_DB_DSN` 按 APP_ENV 三模式推导、非 prod 放行 `PPB_ALLOW_DEV_CODE_SECRET`、migrate 先于启动、启动段 [4.6/6]（RPC 9107 / 健康 9117，plugin 与 gateway 之间）、stop-all 逆依赖序 + 端口兜底加 iam；cmd/server 的 internal_token 门禁在 `PPB_INTERNAL_RPC_TOKEN` 已注入真实凭据时跳过。另将 migrate-user 显式 `-dsn` 契约补丁落进本分支（此前仅存在于 main 的未提交本地改动）。提交 `17023d3`。
  - **跑通验证**：`APP_ENV=sqlite bash scripts/start-all.sh` → **七进程全部健康**（user/im/file/plugin/gateway 健康复用跳过 + iam 新起）；iam `/ping`/`/healthz` 返回 `db:ok`，RPC 9107 监听，日志无 dev token 告警（真实凭据生效）；`data/ppb_iam.db` 7 表建成。
  - 未做（如实）：gateway gRPC upstream 与 `tools/ci.sh` 登记（等 idl/iam.proto 阶段2）；MySQL 实例执行（G6 缺口不变）。

### 遗留与下一步
- [x] 阶段0检查点提交（24e3d89）与阶段1代码提交（6a2251e/39d9ace）——**已推送远端**：ppb-docs `439ffa4..1213639`、ppb-base `18cd1c9..6a2251e`（2026-10-27；ppb-docs 首推 22 端口超时，重试成功）
- [x] 工具链版本：go1.26.0 darwin/arm64 已实测（2026-10-27）；node/git 待补
- [x] gofmt + build/vet + `go test ./server-iam/...` 全绿（2026-10-27 macOS 会话，修复提交 `1389270`）；go.sum 按工作区约定不生成（见 §0）
- [ ] ADR-008 四项待拍板：#3 邮件域落点 / #4 公告去向 / #5 部门负责人列 / #6 工号身份类型（拍板后同步 schema/字典再进对应阶段）
- [x] start-all.sh / stop-all.sh 登记 ✅（2026-10-27，`17023d3`；七进程口径）
- [ ] 剩两处：gateway upstream（等 idl/iam.proto 阶段2）、tools/ci.sh
- [ ] 阶段2 启动项：idl/iam.proto 定稿（依赖 ADR-005 协议库选型 P0）→ handler/网关接线 → OIDC 授权码+PKCE
