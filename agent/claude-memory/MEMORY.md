# Memory Index

- [ppb-wardrobe 仓库结构](ppb-wardrobe-repo.md) — wardrobe-ios-app（含 WardrobeCore）/wardrobe-manage-web 根布局、xcodeproj 生成契约、验证三板斧

- [ppb 系项目本机启动要点](runbook-local-mac.md) — go sdk PATH、start-all migrate -dsn 契约、file 已切 MySQL 显式迁移、camera 手动拉起、六进程端口
- [ppb 文件平台 v2 演进](ppb-file-platform-v2.md) — 刀序路线A、MySQL 已裁决（feat/file-mysql 0f9b319）、未裁决：同库/新库、bug 范围
- [统一 AdminShell + IAM 模式](ppb-adminshell-iam-mode.md) — 2026-10-28 lane B 完工：双模式/红线/命名空间/裁剪规则、测试坑、后端未联调项
- [ppb IAM 业务桥](ppb-iam-business-bridge.md) — 2026-10-28 lane D 完工：/iam/api/v1/business/manage 桥、HMAC 断言、IAMAppKey=file 覆盖、治理 deny 段、CSRF 口径、TestMenuSeedPolicy 存量失败
- [ppb 前端矩阵](ppb-web-frontends.md) — base 8210 / camera 8230 / chat 8220，底座 file: 挂载，dev 可跑 build 注意
- [统一用户中心三端审计](ppb-unified-usercenter-audit.md) — 2026-10-26 裁决不满足；2026-10-27 重写：4 套身份体系指认 + 治理红线（不是 SSO/不合并用户）
- [IAM 统一后台 context 契约](iam-unified-context.md) — 2026-10-28 lane A：/manage/context 字段、file 域现行码、0005 生成物重生成法、历史会话并行双流竞态策略
- [ppb manage 集成轮收口 2026-10-29](ppb-manage-integration-round.md) — USER-9501 已消/iamx 桥接/邀请接受直签/68-case harness/并行会话冻结协议、待并轨项
- [MaxKey/IdP 选型调研](maxkey-idp-evaluation.md) — 2026-10-27：CVE 9.8、OIDC 陷阱、SCIM 仅入向、Casdoor>ZITADEL>Keycloak>MaxKey、issue 幻觉教训
- [ppb-camera AI 相机项目](ppb-camera-ai-camera-project.md) — XcodeGen+13 SwiftPM 包、执行计划 T00-T25；2026-11-04 真机签名已配（个人 Team VKN28YK9M7，regen 丢 Team 需重选）
- [Subagent 主动派发规则](subagent-dispatch.md) —（原文件丢失，待重写）
- [Superpowers 技能触发边界](superpowers-trigger-boundary.md) —（原文件丢失，待重写）
- [ppb-chat 跨业务授权隔离](ppb-crossbiz-authz.md) — 2026-10-26 实施未提交，详录 ppb-chat/.superpowers/sdd/（原文件丢失；其 migrate-user 加固即 start-all 契约漂移来源，见 [[runbook-local-mac]]）
- [ppb-chat 组织域归属裁决](ppb-chat-org-domain.md) — 数据权威=server-im chat_* 表不可清；企业设置页可合并；ppb_user 旧部门表+leader UI 是可清残留
- [chat-desktop 重写进度](chat-desktop-rewrite-progress.md) — M1/M2 完成+M3 五刀，E2E 账号与 MySQL 后端态、permguard bug；2026-11-04 认证窗口重构已提交 55818391
- [iam-web 门户卡片定宽](ppb-portal-card-width.md) — 2026-11-05 定宽 400px 去 min（699e8fa）；三页本就同宽、差异来自跨端对比；Chromium CDP 实测法
- [Go/GORM 坑与约定](gorm-pitfalls.md) — 零值+default 省略列伪装默认值、闭包自身短声明、check 标签、双方言锁、成功信封、iOS 演示模板事实源
- [跨会话并行派发模式](cross-session-dispatch-mode.md) — 无 Agent 工具时 SendMessage 任务书派空闲会话、回执复验、我集成提交（2026-10-28 双会话实战验证）
