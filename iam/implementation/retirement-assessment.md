# server-user 退役判定材料（retirement-assessment）

> 阶段5 P4 决策输入。**只出材料，不做退役动作。** 结论留白（§5 三情景矩阵），由用户拍板。
> 采集方式：四仓只读静态 grep/源码阅读，2026-10-28，未联库、未含运行时流量。
> 采集基线：ppb-base 以 **feat/iam-v0.4 worktree `/tmp/ppb-base-iam-wt`（HEAD `f1495e0`）** 为准（主 checkout 在 feat/file-platform-v2 `bd0fff2`，iam 提交仅到阶段2 初脚手架 `d219219`，**能力面证据以其为过时**——调用面文件两分支已复核一致，见 §7）；ppb-chat `071da7e6` / ppb-camera `20e43b6` / ppb-docs `f9c4704`。
> 权威依据：`iam/adr/架构决策.md`（ADR-003/005/008）、`iam/tech/迁移计划.md`、`iam/implementation/migration-checklist.md`、`iam/implementation/progress.md`。冲突时以上述文档为准并上报。

## 0. 判定语境（一句话）

ADR-003（架构决策.md:24-26）已定方向：server-user 逐步退役，通用账号/资料/认证/平台授权归 server-iam，chat 组织/成员/部门/邀请/组织角色归 server-im。迁移计划.md:42（P4）给出口径：**迁移批次过观察期后停旧认证写入口→明确旧凭证过期窗口→移除旧密码能力与冗余表（清理前保留审计与恢复材料）→调用方迁完后退役 server-user**。阶段执行实况（代码为准，progress.md 阶段表滞后）：阶段2 已收口（MFA/找回/改密/换绑/SMTP，T9-T11）、阶段3 服务侧已落（platform_* 权威 + 管理 API，T12）、阶段4 组织域服务侧已落（server-im chat_* 15 表 + ChatOrgService，T14）、生产前置两项已闭环（T13）；**但网关与全部调用方入口未切**（§1 全部依赖点仍在 user 上）。

## 1. 调用方证据矩阵（谁还在调 server-user）

### 1.1 网关（HTTP 入口 + gRPC 透传 + 基础设施钩子）

| # | 依赖点 | 证据（ppb-base） | 说明 |
|---|---|---|---|
| G1 | user 域 catch-all 路由 | server-gateway/gateway_routes.go:117 | `api.Group("/user").Any("/*path", logoutRevoker, d.registry.Handler())` |
| G2 | 成员端 21 条方法映射 | server-gateway/proxy/method_registry.go:416-510（`RegisterUserDomain`，注释核对 21 条） | 登录/验证码/OAuth 4/绑定 2/会话 3/通讯录 2/资料 1/偏好 2/邀请 2/权限 1/登出 1/密码 1/公告 1 |
| G3 | 9 条 user 白名单路径 | server-gateway/gateway_routes.go:79-88 | login、login-email 2、oauth 4、invitations 2 |
| G4 | 登出撤销钩子 | server-gateway/gateway_routes.go:42-70（`logoutRevoker`） | POST /api/v1/user/logout 命中即撤销 JWT |
| G5 | manage 域整面（37 条路由、67 处 `up.User.*`） | server-gateway/proxy/registry_manage.go:93-473 | 管理后台全部（登录/组织/成员/部门/邀请/公告/审计/管理员/角色/邮件日志）直连 user upstream |
| G6 | im/file 管理动作审计挂 user | server-gateway/proxy/registry_manage.go:222-370（`auditedRPC(... up.User.AdminAudit)`） | 即使 im/file 域管理路由，审计写入仍依赖 user |
| G7 | S3 会话校验 | server-gateway/proxy/session_checker.go:23-27（`ValidateSession` + 30s TTL 缓存） | 网关逐请求查 user 会话状态 |
| G8 | 管理端授权守卫 | server-gateway/gateway_routes.go:130-134（`AdminAuthz`/`RbacVersion` → `d.upstreams.User`） | permguard 版本戳一致性依赖 user |
| G9 | upstream 声明 | server-gateway/proxy/grpc_clients.go:31,52；config/gateway_config.go:145,175；deploy/config/gateway.yaml:22-24 | `ppbchat.user` → 127.0.0.1:9101 |
| G10 | 部署编排 | deploy/docker-compose.yml:37-42,57-74（user + migrate-user 容器及依赖）；deploy/scripts/start-all.sh:38,42,145,195-197（build/migrate/启动段 [3/6]） | 七进程口径之一 |

### 1.2 服务间 gRPC 调用方（两个下游服务，3+2 个解析 RPC + AdminAuthz）

| # | 调用方 | 消费的 user RPC | 装配证据（ppb-base） | 业务消费点 |
|---|---|---|---|---|
| R1 | server-im | `ResolveMembers` / `ResolveMemberIds` / `ResolveMembersByIds`（idl/user.proto:133,153,158） | server-im/internal/rpcclient/user_file_grpc.go:20,29,45,60；cmd/server/main.go:114 | member_id_cache.go:72,104；message_history_service.go:75,184；todo_service.go:102,184；push_fanout_service.go:108；message_flow_service.go:552；conversation_repo.go:249（跨库不 JOIN，姓名/ID 翻译全走 user） |
| R2 | server-im（permguard） | `AdminAuthz` | server-im/cmd/server/main.go:128（`usergrpc.NewUserServiceClient`） | im 管理面授权回源 |
| R3 | server-file | `ResolveMemberIds` | server-file/internal/rpcclient/user_grpc_client.go:25,32；cmd/file/main.go:122,136；config.yaml:93 | owner/operator bizKey→id 翻译（配额计费主体、下载权限比对）；member_id_cache.go:63 |
| R4 | server-file（B8 + permguard） | `ResolveMembersByIds` / `AdminAuthz` | server-file/internal/rpcclient/user_name_client.go:22,32；cmd/file/main.go:138,155 | 管理面 owner 身份反查（file_manage_service.go:5）；file 管理面授权 |
| R5 | server-camera | **无 RPC/HTTP 依赖** | 仅口径注释（cmd/server/main.go:40、internal/service/camera_config.go:18,48 等） | 退役不受 camera 后端影响 |

### 1.3 前端调用面（2 个业务前端仓 + ppb-base 自带管理端；camera 为零）

| # | 前端 | 调用点 | 证据 |
|---|---|---|---|
| F1 | ppb-chat/chat-client（C++/Qt） | **15 处调用点（9 文件）** | 登录 LoginFrame.cpp:344,366,386（login/login-email 2）；OAuth OAuthLoginFlow.cpp:61,134；绑定 EmailBindDialog.cpp:93,121；资料/登出 AppCore.cpp:240,443；改密 AppDialogs.cpp:74；通讯录 ContactsPanel.cpp:138、ContactPickerDialog.cpp:743、SessionListPanel.cpp:379；偏好 ChatPanel.cpp:549,555。（mock/MockGateway.cpp:172-255 另有模拟面） |
| F2 | ppb-chat/chat-desktop（Tauri） | **3 处原生调用 + 双通道 UI** | src-tauri/src/httpapi.rs:139（POST /api/v1/user/login）、:172（logout）；src-tauri/src/session.rs:1100（GET profile）；LoginView.vue:3 legacy 表单与 IAM Tab 并存；src/auth/iam.ts:12（新 OIDC 通道不改旧链路） |
| F3 | ppb-chat/chat-manage-web | 13 个 API 模块全走 /api/v1/manage/*（→ G5 user upstream） | src/api/auth.ts:3（manage/login）；org/{departments:3,members:4,invitations:4,org:3,roles:3}；system/{admins:3,audit:4}；ops/email_log.ts:4；im/announcements.ts:3；api/events.ts:3（MQ 观测） |
| F4 | ppb-base/base-manage-web | 6 处 | src/core/auth.ts:2（manage/login）；src/core/permission.ts:2（me/profile）；src/api/events.ts:3；src/api/org/roles.ts:3；src/api/system/{admins:3,audit:4} |
| F5 | ppb-camera | **0 处** | camera-manager-web 仅 /api/v1/camera/manage/*；camera-ios-app 走 camera 域游客链路。全仓无 /api/v1/user 引用 |
| F6 | ppb-base/iam-web、iam-manage-web | 不依赖 user（直连 9117） | iam-manage-web/src/api/iam.ts:78（`BASE='/iam/api/v1'`）；iam-web 同构 |

### 1.4 规模汇总

**gRPC 调用方 3 个后端服务**（gateway user 域/manage 域/permguard/session-checker + im 解析 3 RPC + file 解析 2 RPC，合计消费 user.proto 95 个 RPC 中的约 60 个）；**HTTP 路由面 58 条**（user 域 21 条 + manage 域 37 条，manage 侧 67 处 `up.User.*` 调用点）；**前端 4 个工程（2 个仓：ppb-chat 三端 + ppb-base base-manage-web）有调用**（chat-client 15 点、chat-desktop 3 点、chat-manage-web 13 模块、base-manage-web 6 点；camera 0）。

## 2. server-user 独有能力承接现状（iam/im 接了多少）

> 表集口径（iam-wt `f1495e0`）：server-user 28 表；server-iam 已建 **30 表**（阶段1 七表 + 阶段2 十三表 + mfa_factors/recovery_codes + platform_* 七表）；server-im 新增 chat_* 组织域 **15 表**（chat_org_model.go 13 + chat_support_model.go 2，`318a6f9`）。目标态 58 表/674 列。

| 能力域（server-user 现状证据） | 承接目标 | iam/im 现状（iam-wt `f1495e0`） | 状态 |
|---|---|---|---|
| 账号/资料/凭证（user/user_identities/user_credentials） | server-iam | 表已建；注册+邮箱密码登录通（iam.proto:51,56,62）；端点 /iam/api/v1/{register/code,register,login,me}（server-iam/internal/handler/iam_http_handler.go） | ✅ 承接 |
| OIDC 协议面（IdP：授权码+PKCE/JWKS/刷新轮换/撤销/introspect/userinfo） | server-iam | op.Provider（server-iam/cmd/server/main.go:148）；端点 /authorize /oauth/token /oauth/introspect /revoke /userinfo /keys；dev 客户端已注册 chat-desktop（`c3a0576`）、camera-ios（`f1495e0`） | ✅ 承接 |
| **生产前置两项**（CORS 收紧 + 令牌态复检） | server-iam | CORS 白名单配置化（server-iam/cmd/server/main.go:145-149，`dc238cb`）；token/userinfo 路径复检用户态（internal/oidcstorage/{storage,token,authrequest}.go，`2ab850d`） | ✅ 承接（原 T13 缺口闭环） |
| MFA（T9/T13.5） | server-iam | mfa_factors + recovery_codes 表（domain/mfa_model.go）；TOTP enroll/verify/两阶段登录/reauth（internal/service/mfa_service.go：213 EnrollStart 等；`e6a2c3e`/`44ce2ad`/`a3f261c`；并发修复 `84032f2`/`589edf2`）；端点 /iam/api/v1/mfa/{enroll/start,enroll/confirm,verify,status,recovery-codes} | ✅ 承接 |
| 找回/改密/换绑（T10） | server-iam | /iam/api/v1/password/{forgot,reset}（`6c5a392`，全局撤销）；/iam/api/v1/identity/change-email/{start,confirm}（`f1325f3`，退役值占位）；改密经 reset 流程承载 | ✅ 承接 |
| 邮件真投递（T11） | server-iam | SMTP sender 配置门控装配（internal/service/smtp_delivery.go；deploy/config/iam.yaml，`0eab0aa`） | ✅ 承接 |
| 平台 RBAC/菜单/管理员（阶段3，T12） | server-iam platform_* | platform_* 七表 + platform_admin_sessions（domain/platform_model.go，`50a10b6`）；角色-菜单权威服务（internal/service/platform_service.go，`98a5d1f`）；管理 API /iam/api/v1/manage/{admins,audit,me,menus,permissions,roles,users} + 超管治理（`3763e33`/`d43d30a`） | ✅ 承接（服务侧）；**网关 manage 37 条路由仍指向 user（G5），切换未做** |
| iam-manage-web（TB3/TB3.5） | iam-manage-web | manage API 契约层（`ca418b4`）+ 列表/治理视图接真数据（`6e6542b`/`b81595a`/`19c45c7`）；登出已接 T13 端点（`6deeca0`） | ✅ 承接；base/chat 两个旧管理端仍全量在 user（F3/F4） |
| 组织域表与服务（T14：部门/成员/角色/邀请） | server-im | chat_org_model.go + chat_support_model.go 共 15 张 chat_* 表（`318a6f9`）；服务层（`7dbd908`）；ChatOrgService gRPC（idl/im.proto:506-521：IsMember/WorkspaceMembers/MemberRoles/AcceptInvitation，`e178111`） | ✅ 承接（服务侧）；**网关 G2/G5 与前端 F1/F3 入口未切** |
| 会话管理 S3（user.proto:187-202） | server-iam | iam 侧 logout/reauthenticate 端点 + OIDC revoke/introspect 已有；网关 session_checker（G7）/logoutRevoker（G4）仍绑 user（proxy/session_checker.go:54） | 🔴 未接线（网关侧替代未做） |
| 邮箱验证码登录（user.proto:178,181） | server-iam | iam 仅注册发码（IssueRegisterCode）；无 login-email 端点；旧库迁移映射未定 | 🔴 未承接（含迁移映射） |
| 邮箱绑定（user.proto:170,173，OAuth 侧绑邮箱） | server-iam | iam change-email 为换绑登录邮箱（`f1325f3`）；旧 oauth/bind-email 6 个前端调用点依赖第三方登录通道（未做） | 🔴 未承接（依赖 federation） |
| 第三方登录 federation（oauth_login_service + user_oauth_binding） | server-iam | user_external_identities/identity_providers 表未建（domain 30 表无）；IAM-08 未实现 | 🔴 未承接 |
| 邀请体系（member+admin，user.proto:280-298） | server-im | chat_invitations + chat_invitation_roles 表已建、AcceptInvitation RPC 有（im.proto:521）；成员端 send-code/accept HTTP 与 manage 邀请管理仍走 user（G2/G5、F3 org/invitations.ts:4） | 🔶 表+服务已建，入口未切 |
| 组织管理 HTTP 面（部门/成员/导入/启停/org settings/登录策略） | server-im | 同上：服务侧 ✅（T14），网关 manage 组织路由（registry_manage.go:98-162 共 17 处 up.User）与前端未切 | 🔶 服务已建，入口未切 |
| 通讯录（GetContactTree/SearchMembers，user.proto:27,31） | server-im | WorkspaceMembers 有查询面（im.proto:513）；user 域通讯录路由未切；chat-client 3 个调用点无替代 | 🔶 服务已建，入口未切 |
| 偏好 KV（user_preference/user_setting） | server-iam | iam 无表（user_model.go:40 仅注释提及 KV；30 表清单无）；im 侧仅 chat_user_preference（chat 键，chat_support_model.go）；chat-client ChatPanel.cpp:549,555 无替代 | 🔴 未承接 |
| 邮件域（user_mailbox/user_email_send_log/mail_* 列 + user.proto:136-149 五个 mail RPC） | **无落点** | IAM 侧验证码投递已真（SMTP，T11），但旧邮件域四对象目标仍无；proto 死面不变（全仓无调用方） | ⏸ 待拍板（ADR-008 #3） |
| 公告（user_announcement + user.proto:263-275） | server-im 或冻结 | ppb_im 15 表清单无公告表；chat-manage-web im/announcements.ts:3 仍调 user | ⏸ 待拍板（ADR-008 #4） |
| 服务间解析面（ResolveMembers/Ids/ByIds，R1/R3） | 未指定（iam 或 im） | ChatOrgService 4 个 RPC 无 bizKey↔id 解析面；iam.proto 仍 3 RPC；im/file 8+ 处业务消费点无切换目标 | 🔴 未设计（退役硬阻塞点之一） |
| 审计查询（List{Login,Admin}AuditLogs/Export*，user.proto:232-247） | server-iam audit_events | /iam/api/v1/manage/audit 已开（`3763e33`）；旧 login/admin 审计数据迁入 vs 归档未决（checklist §4-4） | 🔶 端点已开，旧数据去向未决 |
| MQ 事件观测（ListMqEvents/ResetMqEvent，user.proto:253,257） | 无（MQ 已移除） | user 侧遗留接口；chat-manage-web events.ts、base-manage-web events.ts 仍调 | ⏸ 待拍板（随退役下线或迁 event_outbox 观测面） |
| 端侧接线 | 各端 | chat-desktop OIDC 通道 ✅（iam.ts:12 + `c3a0576`）；camera iOS App 层未接（全仓 swift 无 oidc/iam 引用；iam 侧仅注册 dev client `f1495e0`）；C++ chat-client 仅旧链路（F1） | 🔶 desktop ✅ / iOS、C++ 未接 |

> 状态图例（本节）：✅ 已承接 / 🔶 部分承接（服务侧已建、入口未切，或数据去向未决）/ 🔴 未承接 / ⏸ 待拍板。

## 3. 未完成项与待拍板项对判定的影响

1. **ADR-008 四项待拍板**（架构决策.md:48-67 表 + progress.md 后续需要做 #2）：
   - **#6 工号身份类型（最急）**：employee_code 无 identity_type 可落，影响 user_identities 三列唯一键设计 → 阻塞 P3 迁移脚本定稿 → 阻塞退役。
   - **#3 邮件域落点**：mailbox/邮件日志/个人邮件配置四个对象无目标 → 无法出"冗余表清理清单"（P4 要求保留审计与恢复材料）。
   - **#4 公告去向**：user_announcement 不定，chat-manage-web 公告面与 chat-client 补拉端点（G2/F1/F3）无处切。
   - **#5 部门负责人列**：chat_departments 补列或丢弃，影响组织域承接（§2 第 10 行）。
2. **migration-checklist §4 十项未决**（含 user_file 保留与否 §4-2、user_devices §4-3、审计迁入 vs 归档 §4-4、pref_key 拆分清单 §4-9、oauth 双表对账 §4-10）：直接构成 P4"冗余表清理"与 P3 批次清单的输入。
3. **switch_check 8 项**（migration-checklist §3）：P4 停写前的演练门槛（同邮箱不合并/确权映射/bcrypt 兼容/软删不复活/唯一键预检/manifest/回退检查点/旧会话不转 token）。
4. **ADR-005 P0 六项未定**（subject 策略/时限/撤权 SLA/MFA 恢复/HA 指标/方言适配，架构决策.md §ADR-005）：生产开放前置——退役动作含生产切换，受此约束。
5. **迁移计划红线**（迁移计划.md:29-65）：旧会话分批退役不转 token、OAuth 绑定双表"对账→迁移→停双写→退役"、回退不得复活旧凭证。
6. **环境债**（progress.md §0/遗留）：ppb-docs stash `rollback-before-pull-20261027` 未对账；MySQL 实例执行（G6）未做——影响演练结论可信度。

## 4. 退役前置条件清单

> 状态口径：✅ 已满足 / ⬜ 未满足 / 🔶 部分满足（服务侧已建、切换未做等）/ 🔴 未承接或未设计 / ⏸ 待拍板。**本表只登记事实，不构成结论。**

| # | 前置条件 | 状态 | 证据 |
|---|---|---|---|
| C1 | ADR-008 #6 工号身份类型拍板（唯一键设计） | ⏸ | 架构决策.md ADR-008 表 #6；progress.md 后续需要做 #2 |
| C2 | ADR-008 #3 邮件域落点拍板 | ⏸ | 同上 #3；migration-checklist §4-1 |
| C3 | ADR-008 #4 公告去向拍板 | ⏸ | 同上 #4；migration-checklist §4-5 |
| C4 | ADR-008 #5 部门负责人列拍板 | ⏸ | 同上 #5；migration-checklist §4-6 |
| C5 | ADR-005 P0 六项固定（subject/时限/SLA/MFA 恢复/HA/方言） | 🔶 MFA 恢复已实现（recovery_codes，`e6a2c3e` 系）；其余五项 ⏸/⬜ | 架构决策.md ADR-005；iam-wt domain/mfa_model.go |
| C6 | 阶段2 剩余收口：MFA ✅、找回/改密/换绑 ✅、SMTP ✅（T9-T11，`e6a2c3e`…`0eab0aa`）；第三方登录 federation ⬜（IAM-08）；邮箱验证码登录 ⬜ | 🔶 | §2 各行 + iam-wt 端点清单（iam_http_handler.go） |
| C7 | 生产前置两项：Provider CORS 收紧、签发/刷新复检 user_status | ✅ | server-iam/cmd/server/main.go:145-149（`dc238cb`）；internal/oidcstorage（`2ab850d`） |
| C8 | 阶段3 platform_* 权威 + 管理 API | ✅ 服务侧已落（T12：`50a10b6`/`98a5d1f`/`3763e33`）；**网关 permguard/RbacVersion 切换与撤权缓存失效重设计 ⬜**（G8 仍绑 user；ADR-008 #12） | 🔶 | §2 平台 RBAC 行；gateway_routes.go:130-134 |
| C9 | iam-manage-web 落地（管理端承接） | ✅ 已接真数据（TB3/TB3.5：`ca418b4`/`6e6542b`/`b81595a`/`19c45c7`）；**旧管理端切换 ⬜**（见 C17） | ✅/⬜ | iam-wt iam-manage-web/src/api |
| C10 | 组织域迁 server-im（chat_* 表 + 通讯录 + 邀请） | ✅ 服务侧已落（T14：15 表 `318a6f9` + 服务 `7dbd908` + ChatOrgService `e178111`）；**网关/前端入口切换 ⬜**（G2/G5、F1/F3） | 🔶 | idl/im.proto:506-521；§2 组织域行 |
| C11 | 偏好/设置 KV 表（user_preference/user_setting） | ⬜ | iam-wt 30 表清单仍无（user_model.go:40 仅注释）；im 侧仅 chat_user_preference（chat 键）；ADR-008 #3 建议 |
| C12 | 服务间解析面替代（ResolveMembers/Ids/ByIds 新落点 + im/file 切换） | ⬜ 未设计（ChatOrgService 4 RPC 无解析面，idl/im.proto:506-521） | §2 解析面行；R1/R3 全部消费点 |
| C13 | 网关 S3 会话校验/登出钩子 IAM 化（替 G4/G7） | ⬜ | session_checker.go:23；gateway_routes.go:42-70 |
| C14 | 邮箱验证码登录/邮箱绑定 iam 化（替 F1 login-email/bind 6 个调用点） | ⬜ | §2 邮箱验证码行 |
| C15 | chat-client 15 调用点迁移 | ⬜ | §1.3 F1 |
| C16 | chat-desktop legacy 登录链路收敛到 IAM（3 原生点 + LoginView 双通道裁撤） | ⬜ | §1.3 F2 |
| C17 | chat-manage-web + base-manage-web 管理面切换（19 处模块引用） | ⬜ | §1.3 F3/F4 |
| C18 | server-im/server-file gRPC 依赖切换（R1-R4） | ⬜ | §1.2 |
| C19 | 网关 user 域 21 路由 + manage 域 37 路由下线（G1-G6） | ⬜ | §1.1 |
| C20 | P3 数据迁移完成 + switch_check 8 项通过 + 观察期 + 旧凭证过期窗口 | ⬜ | migration-checklist §3；迁移计划.md:42 |
| C21 | 旧表归档方案（审计/恢复材料保留）+ 冗余表清理清单 | ⬜ | 迁移计划.md:42；checklist §4 |
| C22 | 部署面退役（docker-compose user/migrate-user、start-all/stop-all [3/6] 段、gateway.yaml ppbchat.user） | ⬜ | G9/G10 |
| C23 | camera iOS App 层 IAM 接线（端侧 OIDC 通道） | ⬜ | iam 侧 dev client 已注册（`f1495e0`）；camera-ios-app 全仓 swift 无 oidc/iam 引用 |

## 5. 三类结论情景（证据矩阵——结论留白，由用户拍板）

> 判读规则（建议）：C1-C5 为拍板类；C6-C14 为能力补齐类（含服务侧已落、切换未做的 🔶 项）；C15-C19、C23 为调用方切换类；C20-C22 为数据与收尾类。任一 🔴/⬜/⏸ 未清零即落入"不可退役"或"条件满足后可退役"。

| 条件组 | 情景一：可退役（全部 ✅） | 情景二：条件满足后可退役 | 情景三：不可退役 |
|---|---|---|---|
| C1-C5 拍板类 | ✅ 已拍板且 schema/字典同步修订 | ⏸ 部分拍板（缺项：____） | ⏸ 未拍板（缺项：____） |
| C6-C14 能力补齐类 | ✅ 全部落地 | 🔶 服务侧已落、缺口在：____ | 🔴 未承接项仍在（现状：federation/邮箱验证码登录/偏好 KV/解析面未做） |
| C15-C19、C23 调用方切换类 | ✅ 4 仓调用面清零 | 🔶 chat-desktop 已双通道、其余未动（缺口：____） | ⬜ 调用面仍全量在线（现状如此：58 条路由 + 18 处调用点 + iOS/C++ 未接） |
| C20-C22 数据收尾类 | ✅ 观察/归档完成 | ⬜ 演练未做 | ⬜ P3 未启动（现状如此） |
| **结论** | ________ | ________ | ________ |

**当前时点的事实锚点**（供填空参考，非结论）：iam/im 能力面已大面积就绪（MFA/找回/改密/换绑/SMTP/平台授权/组织域 15 表，T9-T14）；但网关与调用方入口**零切换**（G1-G8、R1-R4、F1-F4 全量在 user）；管理后台 37 条路由整面直连 user（G5）；服务间解析面无替代设计（C12）；federation、邮箱验证码登录、偏好 KV、iOS/C++ 端侧未承接（C6/C11/C23）。

## 6. 分批退役路径建议（对齐迁移计划 P4；写入口 → 读出口 → 旧表归档）

> 本节为路径草案，供阶段5 演练排期讨论；每批入口/出口均在 §4 前置条件清零后执行。

- **批次0 拍板与设计前置**：C1-C5 拍板 → 同步修订 schema.sql/字段字典/验收（ADR-008 处置原则）；产出 C12 解析面替代设计（iam 或 im 承载 ResolveMembers/Ids/ByIds）与 C13 网关会话/撤权 IAM 化设计（并入阶段3 缓存失效重设计）。
- **批次1 写入口停用**（对齐 P4"停用旧认证写入口，明确旧凭证过期窗口"）：
  1. 成员端写链路：login/login-email/oauth/bind/invitations accept/change-password → chat-client、chat-desktop 切 IAM OIDC（chat-desktop 双通道模式 iam.ts:12 为样板），网关下 9 条白名单（G3）与对应 user 域路由；
  2. 管理端写链路：manage 登录/组织/成员/邀请/公告/角色 → iam-manage-web（platform_*）+ chat 管理面（im 组织域）；
  3. 旧 JWT/会话按批次定过期窗口，观察期起步（C20）。
- **批次2 读出口替换**（读路径切新权威后再撤 user RPC 面）：
  1. 网关 G7 session_checker / G4 logoutRevoker / G8 permguard 重接 iam（阶段3 产出）；
  2. server-im、server-file R1-R4 解析面切新落点（C12 设计落地；member_id_cache 8 处消费点随切）；
  3. 通讯录/资料/偏好读出口切 im/iam（C10/C11）；管理审计与 G6 auditedRPC 审计写入切 iam audit_events；
  4. 邮件域死面（user.proto:136-149）与 MQ 遗留面（:253,257）随拍板结论直接下线或冻结。
- **批次3 旧表归档与移除**（对齐 P4"移除旧密码能力与冗余表，清理前保留审计与恢复材料"）：
  1. 旧 auth_sessions 分批退役（switch_check #8：抽查旧 JWT sid 无对应行、网关不回查旧表）；
  2. 28 表按 checklist §1 去向归档（审计/恢复材料留档，含 ADR-008 #3/#4 冻结项）；
  3. 撤部署：docker-compose user/migrate-user、start-all/stop-all [3/6]、gateway.yaml ppbchat.user、idl/user.proto 与 server-pkg/grpc_gen/user 收编；
  4. 退役后回验：C15-C19 调用面复扫为零 + 网关路由表无 user 段。

## 7. 采集口径与限制

- 静态源码 grep（`server-user|UserServiceClient|userpb|/api/v1/user|/api/v1/manage` 等多模式交叉），未做运行时流量/日志佐证；"无调用方"结论仅指源码面。
- 未含 build 产物（dist/、node_modules/ 排除）；chat-desktop 前端侧经 Tauri 原生（src-tauri）承载，已覆盖。
- camera 域只验了 /api/v1/user 与 auth 前缀，camera 管理面（/api/v1/camera/manage/*）不依赖 user（camera_registry.go 无 User 引用）。
- **ppb-base 双分支口径**：主 checkout（feat/file-platform-v2）iam 提交止于 `d219219` 脚手架；能力面证据全部取自 feat/iam-v0.4 worktree `/tmp/ppb-base-iam-wt`（HEAD `f1495e0`）。调用面文件两分支已复核一致（registry_manage.go 67 处 `up.User.*`、session_checker.go:54 `ValidateSession`、method_registry.go:416/419 `RegisterUserDomain` 21 条均不变）。
- 本文档不修改任何代码/schema/验收；与 progress.md、migration-checklist.md 冲突时以上述为准并上报。progress.md 阶段表（阶段3/4/5 ⬜）滞后于 iam-wt 代码实况，能力判定以代码为准。
