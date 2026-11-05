---
name: runbook-local-mac
description: ppb 系项目本机启动要点（go sdk 路径、start-all 契约、file 存储后端、camera 手动拉起）
metadata:
  node_type: memory
  type: project
  originSessionId: 60254c68-00fb-4b08-b267-848f4f83d2fa
  modified: 2026-11-03T00:51:28.965Z
---

ppb 工作区根：/Users/pipi-ban/Desktop/code/vscode（含 ppb-base/ppb-camera/ppb-chat/ppb-docs/plans）。
Claude 的 shell 无 go：须 `export PATH=/Users/pipi-ban/sdk/go1.26.0/bin:$PATH`。
Claude shell（尤其后台任务）连 node/npm 都没有——/opt/homebrew/bin 也不在 PATH。跑 chat-desktop：`PATH=$HOME/.cargo/bin:/opt/homebrew/bin:$PATH npm run tauri dev`（在 chat-desktop/ 下；**~/.cargo.bin 必须排在 /opt/homebrew/bin 之前**，否则 homebrew cargo 1.68 解析不了 keyring4 依赖 apple-native-keyring-store 的 edition-2024 直接 exit 101；前端进程用的 node 是 homebrew 25.2.1）。窗口就绪判据：pgrep target/debug/ppb-chat-desktop；截图用 CGWindowList 取 window id + screencapture -l<id>。

环境坑（2026-10-27 实测，Desktop 在 iCloud 同步范围）：
- swift test 在 Desktop 下 codesign 拒签（com.apple.provenance/fileprovider xattr）→ 必须 `swift test --scratch-path /tmp/<名>`；xattr -cr 清了会被重新打上。
- File Provider 目录枚举间歇抖动（ls/cd 偶报 No such file）→ sleep 3-5s 重试即恢复，非目录真消失。
- Xcode 27.1 / Swift 6.4；iPhone 17 模拟器 UDID 0F3D5F8D-B736-4691-A8F5-25CA525FBFF3。

ppb-base 后端（SQLite 零依赖态）：`cd ppb-base/deploy && APP_ENV=sqlite bash scripts/start-all.sh`
- file 已切 MySQL 显式迁移（2026-10-28，feat/file-mysql 分支 0f9b319）：migrate-file CLI 显式 -dsn（对齐 migrate-user 契约）；MySQL 启动只校验不自迁移（空库 fail-fast 指向 CLI），SQLite 开发态保留启动自迁移；start-all migrate 阶段已含 file。本机 dev 库=db.env → 127.0.0.1 ppb-mysql 容器（mysql:8.0.45，root，口令=容器 MYSQL_ROOT_PASSWORD，ppb_file 已有存量数据，表为 AutoMigrate 建制）。分支从 feat/iam-v0.4 尖端切出（含 iam stage-2 提交）；在跑的 file 9114 旧进程是自迁移版二进制，start-all 重建后自然换新。
- **七进程** user/im/file/iam/gateway（start-all 顺序拉起；plugin 服务已整体移除 8f8a6f2）+ camera 手动；健康口 9111/9112/9114/9115/**9117**/8080，iam RPC 9107，pid 在 deploy/run/，日志在 deploy/logs/，幂等可重跑（已起健康即跳过）。
- iam（2026-10-27 入 start-all）：`deploy/data/ppb_iam.db`（7 表起步）；dev 拉起靠内置默认 config + `PPB_ALLOW_DEV_CODE_SECRET`（start-all 非 prod 自动放行）；`deploy/config/iam.yaml` 是生产模板（空值 fail-fast）。
- 2026-10-27 实测坑①：新版 migrate-user CLI 要求显式 -dsn（不读环境变量）——start-all 已传 `-dsn "${USER_DB_DSN:-data/ppb_user.db}"`，**该补丁已落 feat/iam-v0.4 分支**（此前仅 main 本地未提交）；migrate-im 老契约可裸调，migrate-iam 同款显式 -dsn。
- 坑②：config/file.yaml 曾留 storage_backend: minio（127.0.0.1:9000 SeaweedFS 网关，已不在跑、s3.json 缺失），sqlite 零依赖态应 local（备份 file.yaml.bak-claude）；snapshot 配置与代码默认均为 local。
- server-user 已于 2026-10-28 彻底删除；用户域已迁 ppb_iam（user/user_credentials/user_identities/user_preference 四表，E2E 口令 bcrypt 直写于此）。**2026-11-03 已 DROP 五库**：ppb_user（旧用户库）、ppb_user_b1t/ppb_im_b1t/ppb_file_b1t/ppb_camera_t14_test（测试克隆）——现存仅 ppb_camera/ppb_file/ppb_iam/ppb_im 四库。ppb_im 内 event_outbox/chat_sessions 为注册未接线死表（0 行），真清理需先删 server-im AutoMigrate 注册再 DROP（下轮候选）。camera 管理面 8 条 /api/v1/manage/camera/* 已通（9837960）；工号登录 (4,legacy) resolver 已落（0241ff8）；server-camera 不在 start-all 内，手动拉起：`cd deploy && PPB_ALLOW_DEV_JWT=1 PPB_INTERNAL_RPC_TOKEN=$(cat run/internal-rpc-token) CAMERA_DB_DSN=root:${PPB_DB_PASSWORD}@tcp(127.0.0.1:3306)/ppb_camera?charset=utf8mb4&parseTime=True&loc=Local（MySQL 态，2026-10-28 起全后端统一 APP_ENV=dev+MySQL） nohup ./bin/camera >> logs/camera.log 2>&1 &`（RPC 9106 / 健康 9116，无 config.yaml 时用内置默认值）。
- seed admin：config/user.yaml（admin / 开发默认口令，D4 闸门 dev 态需 PPB_ALLOW_DEV_JWT=1，start-all 已处理）。
- 2026-11-03 新坑①（start-all 幂等陷阱）**已修**（53c0a7a，feat/w2-start-all-stale 分支）：start-all 健康进程现在比对二进制 mtime vs 进程启动时间，旧则自动换新重启；build 段改为「内容一致保留」（cmp 后不刷 mtime），重跑幂等。手动判旧兜底：`go version -m deploy/bin/<svc> | grep vcs.revision` 对比 HEAD。
- 2026-11-03 permguard 间歇 403（MANAGE-0004）**已修**（3e9ff89，同分支）：根因两个——①RbacVersion=MAX(authz_version) 带 deleted_flag=0 过滤（软删最大行→时钟回退）；②AdminAuthz 回每管理员个人版本 vs 网关拿全局 MAX 校验（他人版本高→你永久 403）。修复=去过滤+快照盖全局戳，无 DDL，网关零改动。终验：双超管 manage 读路径各 20× 零 403。注意：**造号 provision 面要求验证过 IAM 断言**（TTL 30s），自铸 legacy manage JWT（dev secret ppbchat-dev-jwt-secret, typ=manage, biz_key=超管 plat_ 键）只能走读路径——USER-0006 是设计内 fail-closed，E2E 造号仍走 DB 直写。超管现网：plat_8fc709333e9d4c0f / plat_b50094a28f4143e2。
- 2026-11-03 已知遗留：server-gateway 根包测试在本机挂起超时（TestPing 引擎构建族；TestFileProxyManageTokenRejected 等）——**预先存在**（基线 b971558 同挂），gateway 7 子包全绿；非本轮引入，未修。
- 2026-11-03 新坑②（IAM OIDC 登录链）：chat-desktop 缺省 issuer=网关透传 `http://127.0.0.1:8080/iam`，iam 须同时具备 1df5ebb 的 /iam 前缀剥离别名 + 启动 env `IAM_ISSUER_URL=http://127.0.0.1:8080/iam`（discovery issuer/端点须与客户端逐字一致）。**start-all 已内置该缺省**（a0843af）。快速诊断：`curl :8080/iam/.well-known/openid-configuration` 应 200 且 issuer=:8080/iam。
前端见 [[ppb-web-frontends]]。原 C++/wxWidgets 相关内容随 2026-10-27 记忆目录被清空丢失。

git 远端（2026-11-04）：origin（git@github.com:maibanku/ppb-base.git）SSH 间歇 publickey 失败（ssh-agent 无 identities、直连时好时坏）——拉推改用 HTTPS URL 直调：`git fetch/push https://github.com/maibanku/ppb-base.git ...`（凭据 osxkeychain 可用；全局配置混入 Windows 的 credential.helper=wincred，每次打无害警告）。push 经 URL 不刷新本地 tracking ref，需补一次 fetch。**2026-11-04 分支已收拢**：w1/w2/camera 三 lane 全部 ff 并入 main 并推送（main=6309abe），本地+远端功能分支全删、ppb-base-wt-w1 worktree 已移除，仓库仅剩 main；后续新工作从 main 重新切 lane。
