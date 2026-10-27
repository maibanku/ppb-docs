# 阶段1 迁移对照清单（migration-checklist）

> 基于文档与 server-user 代码静态对照，2026-10-27，未经联库验证。权威以 `tech/迁移计划.md` 与 ADR 为准；本清单是迁移演练执行底稿，冲突时上报不静默改。
> 代码基线：ppb-base feat/iam-v0.4 起点 `18cd1c9`（progress.md §1）。旧库 = server-user domain 28 表；目标 = `tech/sql/schema.sql`（ppb_iam / ppb_im）。阶段口径对齐迁移计划 §3：P1 只建表不迁数据，P2 管理端确权，P3 数据迁移，P4 退役。

## 1. 现存表 → 目标去向总表

rbac/menu 系属阶段3（platform_* 替换），阶段1 不动。

| 旧表（server-user domain） | 去向 | 阶段 | 备注 |
|---|---|---|---|
| user | server-iam：user（主体）+ user_profile（资料拆出） | P1建/P3迁 | user_id/user_biz_key 原值迁入；mail_* 两列去邮件域（§4-1） |
| user_identities | server-iam：user_identities；oidc:* 行 → user_external_identities（表 P2 建） | P1建/P2-3迁 | provider 字符串→identity_type 数值化；工号类型缺失（§4-8） |
| user_credentials | server-iam：user_credentials | P1建/P3迁 | credential_hash→password_hash；bcrypt 兼容验证前置（§3-3） |
| user_oauth_binding | server-iam：user_external_identities（与旧 oidc:* 行对账） | P2-3迁/P4退役 | 对账→迁移→停双写→退役旧权威（迁移计划 §2） |
| user_admin | server-iam：platform_admins（表 P2 建）；密码并入 user_credentials | P2确权/P3迁 | 独立主体不按邮箱直并；保留旧 admin_id/biz_key 可追踪映射 |
| user_preference | server-iam user_preference；聊天键拆 ppb_im chat_user_preference | P3迁 | pref_key 归属清单待定（§4-9） |
| user_setting | server-iam：user_setting | P3迁 | 全局 KV 同构（corp_name 等） |
| user_mailbox | 邮件域（迁移计划 §2）；目标 4 库无落点 | P3 | 待 ADR（§4-1） |
| user_email_send_log | 邮件域/归档；目标无落点 | P4评估 | 待 ADR（§4-1） |
| user_file | 无目标表；头像改由 user_profile.avatar_file_key 直存 file_biz_key | P3/P4 | 表保留或退役待决策（§4-2） |
| tenants | server-im：chat_workspaces | P3迁 | tenant_id→chat_workspace_id 原值映射 |
| memberships | server-im：chat_memberships；部门列 → chat_membership_departments | P3迁 | member_status 1/2/3 与软删语义原样保留，不复活 |
| department | server-im：chat_departments | P3迁 | 新增 workspace 维度；leader_user_id 无对应列（§4-6） |
| user_department | server-im：chat_membership_departments（is_primary=1） | P3迁 | 旧 1:1 口径 → 新支持多部门 |
| invitations | server-im：chat_invitations + chat_invitation_roles（新表） | P3迁 | token_hash(hex)→token_digest(BINARY(32))；invited_by(管理员键)→inviter_membership_id 需确权翻译；预分配部门列无对应 |
| roles | org 域→chat_roles；platform 域→platform_roles | 阶段3 | 按 role_scope+app_key 拆解 |
| permissions | chat 域码→chat_permissions；其余→platform_permissions | 阶段3 | 现目录权威在 app_catalog.go 代码（base/chat/camera） |
| role_permissions | 按 app_key 转 chat_role_permissions + platform_role_menus/platform_admin_roles | 阶段3 | 新模型不维护 role_permissions 双权威；无页面映射的权限注册 operation 隐藏节点 |
| membership_roles | server-im：chat_membership_roles | 阶段3 | 组织关系随 P3 批次走 |
| admin_roles | server-iam：platform_admin_roles（按 app_key 核对） | 阶段3 | 仅 role_scope=platform 行可迁 |
| manage_menus | server-iam：platform_menus（按实际表核验，不能假定已有） | 阶段3 | biz_key 寻址→ID 寻址；perm_code 改经 platform_menu_permissions 关联；visible→is_hidden 语义反转 |
| manage_role_menus | server-iam：platform_role_menus | 阶段3 | 全量替换物理删插口径保持 |
| rbac_revision | 退役：由 applications.authz_version 等分列版本取代 | 阶段3替换/P4退役 | 撤权缓存失效机制需重设计 |
| auth_sessions（旧） | 不迁：旧会话分批退役，不转 IAM token | P4退役 | 与 P2 新建同名表不同构（sid/BizKey→session_digest） |
| user_devices | 无目标表；新 auth_sessions.device_label 非等价聚合视图 | P4评估 | 待决策（§4-3） |
| login_audit_logs | server-iam：audit_events（迁入或仅归档） | P3/P4 | 列映射见 §2.6；是否迁入待定（§4-4） |
| admin_audit_logs | 同上 | P3/P4 | 同上 |
| user_announcement | 聊天业务；ppb_im 15 表清单无公告表 | 待定 | 待 ADR（§4-5） |

注：`MailBlocklistEntry` 为编译兼容空存根（代码注释称 ppb_mail 已移除），非表。

## 2. 阶段1 涉及表的列级映射（旧→新；四柱=create_time/update_time/deleted_flag/deleted_time，原值迁）

### 2.1 user ← 旧 user
| 旧列 | 新列 | 说明 |
|---|---|---|
| user_id / user_biz_key | 同名 | 原值保留（主键/业务键） |
| last_login_at | last_login_at | 同名原值 |
| 四柱 | 同名 | 原值 |
| user_name | →user_profile.user_nickname | 资料拆出 |
| avatar_user_file_id | →user_profile.avatar_file_key | ID 链接→业务键：经 user_file.file_biz_key 翻译 |
| mail_signature / mail_notify_enabled | 无对应 | 邮件域，阶段1 不落（§4-1） |
| （无） | user_status | 新列：按 memberships.status 原值 1/2→1/2、deleted_flag=1→3；勿沿用旧 AccountStatusOf 把 suspended 折成 3 的展示口径 |
| （无） | security_version / disabled_at | 新列，默认 1 / NULL |

### 2.2 user_profile（新生成，旧无对应表）
| 旧源 | 新列 | 说明 |
|---|---|---|
| 新生成 | user_profile_id / user_profile_biz_key | 派生规则待定（§4-7） |
| user.user_id | user_id | 原值引用 |
| user.user_name | user_nickname | 昵称（旧姓名语义） |
| user.avatar_user_file_id→user_file.file_biz_key | avatar_file_key | 翻译链，非直拷 |
| （无） | language_code / time_zone / profile_version | 新列默认 zh-CN / Asia/Shanghai / 1 |

### 2.3 user_identities ← 旧 user_identities
| 旧列 | 新列 | 说明 |
|---|---|---|
| user_identity_id / user_identity_biz_key / user_id | 同名 | 原值保留 |
| provider='email' | identity_type=2 + identity_namespace='global' | 字符串→数值类型 |
| provider='employee_code' | 无对应类型（identity_type 仅 1/2/3） | 待 ADR（§4-8） |
| provider='oidc:*' | 不入本表 | P2 迁 user_external_identities（identity_providers 先建） |
| subject + normalized_value | normalized_value | 唯一键由原文(subject)变规范化口径，大小写变体预检撞键（§3-5） |
| verified_at | verified_at | 同名原值 |
| last_used_at | 无对应列 | 审计留档 |
| （无） | identity_status | 新列：软删/退役行=3，行保留以占唯一键 |
| uk_identity(provider,subject) | uk(type,ns,normalized_value) | 唯一键重构，旧 uk 含软删行口径继续成立 |

### 2.4 user_credentials ← 旧 user_credentials
| 旧列 | 新列 | 说明 |
|---|---|---|
| user_credential_id / user_credential_biz_key / user_id | 同名 | 原值保留 |
| credential_type | credential_type | 同名（password） |
| credential_hash | password_hash | VARCHAR(128)→VARCHAR(512)，须含算法参数 |
| login_fail_count | password_fail_count | 双单词改名 |
| lock_until / revoked_at | 同名 | 原值 |
| last_used_at | 无对应列 | 审计留档 |
| （无） | credential_version / changed_at | 新列：默认 1 / 置迁移时间或取旧 update_time（演练定） |

### 2.5 verification_challenges
全新表，无旧对应（旧验证码仅 user_email_send_log 发送日志，不存挑战）；无数据迁移。
### 2.6 audit_events ← 旧 login_audit_logs / admin_audit_logs（是否迁入待 §4-4）
| 旧列 | 新列 | 说明 |
|---|---|---|
| user_biz_key（login）/ actor_biz_key（admin） | actor_key | 操作者业务键 |
| 来源表判定 | actor_type | user/admin/system |
| event_type / action | action_code | 动作 |
| result（success\|fail） | action_result（success/failure） | fail→failure 口径转换 |
| admin: target_type / target_biz_key | target_type / target_key | 列改名 |
| request_id | request_id | 同名 |
| detail / identity_hint+reason_code | event_details | 脱敏重组；login.user_id=0（未知账号尝试）落点待定 |

### 2.7 event_outbox
全新表，server-user 无 outbox；MQ 历史事件不迁移。

## 3. switch_check（切换前检查清单）

| # | 检查项（对齐迁移计划红线） | 怎么查 |
|---|---|---|
| 1 | 同邮箱不自动合并：跨用户重复邮箱进人工处置清单 | 旧库 user_identities 按 provider='email'、lower(subject) 分组，count(distinct user_id)>1 的行 |
| 2 | 旧管理员确权映射：不按邮箱直并，确权后迁 platform_admins 并留旧 ID/键映射 | user_admin.admin_account 左连 user_identities(email) 出候选映射表，逐行人工签核 |
| 3 | 密码哈希兼容：bcrypt 算法/参数（现库 DefaultCost）验证一致才受控迁移，否则首登迁移或重置 | 抽样 credential_hash 前缀（$2a/$2b$）与 cost 位；用已知明文测试向量过新侧校验 |
| 4 | 软删/停用不复活：迁移后旧 deleted/suspended 行不得以有效态出现 | 迁移前后对账计数：旧软删+停用数 = 新 user_status∈{2,3}∪identity_status=3 行数，差异须为 0 |
| 5 | 唯一键口径变化：原文唯一→规范化唯一，大小写变体将撞 uk | 新键口径预检：GROUP BY identity_type,identity_namespace,lower(subject) HAVING count(*)>1 |
| 6 | 映射版本与批次记录：batch_id、映射版本、切换时间、旧凭证状态、行数/校验和 | 迁移工具产 manifest 落档；切换前核对 manifest 与两侧行数一致 |
| 7 | 回退检查点：迁移后的改密/停用/绑定/角色变更须先回补旧库或锁定再回退，禁止复活旧密码 | 扫批次时间点之后 user_credentials.update_time 与审计行变更清单，逐条裁决回补 |
| 8 | 旧会话不转 IAM token：旧 auth_sessions 分批退役 | 切换后抽查旧 JWT sid 在 ppb_iam 无对应行；网关/管理端不再回查旧表 |

## 4. 未决项（待 ADR/用户决策）

| # | 未决点 | 影响 |
|---|---|---|
| 1 | 邮件域去向：mail_signature / mail_notify_enabled / user_mailbox / user_email_send_log，迁移计划指邮件域，但目标 4 库 schema 无落点，且代码注释称 ppb_mail 已移除 | §1 四行悬置 |
| 2 | user_file 保留或退役（avatar 改 avatar_file_key 后历史行及其他 purpose 消费方待盘） | §1/§2.2 |
| 3 | user_devices 去向（device_label 非等价聚合视图） | §1 |
| 4 | 旧审计迁入 audit_events 还是仅归档（含 login.user_id=0 落点） | §2.6 |
| 5 | user_announcement 归属（ppb_im 15 表清单无公告表） | §1 |
| 6 | department.leader_user_id 在 chat_departments 无对应列 | §1 |
| 7 | user_profile 主键/biz_key 派生规则（旧无对应行） | §2.2 |
| 8 | employee_code 登录身份类型缺失（identity_type 仅 username/email/phone；工号另挂 chat_memberships） | §2.3 |
| 9 | user_preference 键拆分清单（iam 通用键 vs chat_user_preference） | §1 |
| 10 | oidc:* 行与 user_oauth_binding 双表对账口径（依赖 P2 建 identity_providers） | §1/§2.3 |
