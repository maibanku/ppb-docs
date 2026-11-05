# IAM 统一后台 context 契约与双流竞态（2026-10-28）

- `/iam/api/v1/manage/context?surface_key=`（缺省 platform）已落地：admin 含 `user_biz_key`（网关桥 IAMContext.UserKey 消费）、applications（活跃域+authz_version）、app_perms（全域不过滤 surface）、menus（仅 dir/page、`/{app_key}{route}` 规范路径、is_super 仅 iam 入口引导不通配业务）。Cookie `ppb_iam_session` Path=/（非 /iam）。网关桥 `fetchIAMContext` 即以本端点为权威校验（服务间转发 Cookie）。
- file IAM 应用域持现行服务码 file.read/quota/recycle/takedown/orphan（网关 `bridgeIAMAppKey` 把 /api/v1/manage/file/* 从 chat 重映射到 file 域）+ 7 规划码并存；CatalogVersion 2026.10.28-2。
- `deploy/sql/ppb_iam/0005_platform_seed.sql` 是**生成物**：`UPDATE_SQL_MIRROR=1 go test ./internal/platformregistry/ -run TestSQLMirror_InSync` 重生成（InSync 绊线）。
- 治理写门禁 requireManage(establish, govCode)：超管旁路或 iam 域 iam.role/menu/admin.manage 码。
- **双流竞态教训**：历史会话 60254c68 与 Codex 派发 lane worker 并行写同仓（进程 `claude --resume=60254c68…`，以用户身份提交，如 a6ecbbd 明示合并"批次7 流B"）。策略：新文件承载主体、共享文件 Edit 前必重读（mtime 校验）、小步增量、提交/汇报前再对账 HEAD；勿 kill 对方进程。
