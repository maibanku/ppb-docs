---
name: ppb-file-platform-v2
description: 文件平台 v0.1 设计基线落地——演进步法（路线A）、MySQL 已裁决、分支与刀序
metadata:
  node_type: memory
  type: project
  originSessionId: a0f2d8a5-2fe0-4328-9b13-f2a136bfc184
  modified: 2026-10-27T17:17:43.081Z
---

ppb-docs/file v0.1（2026-10-27 基线）在 ppb-base 演进（不新建仓库）。刀序（路线A：正确性优先）：①止血已知 bug →②v2 schema 落库+file_applications/存储实例配置表 →③引用生命周期+配额账本 →④直传通道反转（对象存储预签名）→⑤兼容适配器切读（旧 proto 16 RPC 映射新引用/签发）→⑥file-web/file-manage-web/file-console-bff →⑦file-worker 媒体 P0.1。

已裁决：**MySQL 一刀切**（2026-10-28 落地 migrate-file CLI + MySQL 启动只校验，feat/file-mysql 0f9b319；SQLite 仅开发态自迁移保留）；**止血范围=4 项数据/配额正确性**（2026-10-28 落地 feat/file-platform-v2 bd0fff2：回收站保护 GC 谓词、同批共享 blob 计数、GC 认领互斥 ClaimGCBlob、对账含回收站计费；thumb URL/单缩略规格/后端假路由/残片清理 4 项显示层延后）。GC 谓词双方言验证含 env 门控 MySQL 集成测试首例（PPB_FILE_MYSQL_DSN，专用空库）。
未裁决：v2 表同库（deploy/sql/ppb_file/v2）vs 新库——倾向同库。
注意：feat/file-platform-v2 分支混入并行 iam OIDC/iam-web 提交（e1d7c73..d219219），file 侧仅 0f9b319/bd0fff2 两笔；工作树仍有 iam 未提交物。

迁移计划问题清单基线 commit 18cd1c9，其后 server-file 无改动（清单仍有效）。ppb_file 现库表为 AutoMigrate 建制（uni_file_file_biz_key 命名特征），与归档 DDL 有轻微漂移，v2 版本化迁移时统一。相关：[[runbook-local-mac]]、[[ppb-crossbiz-authz]]、[[gorm-pitfalls]]
