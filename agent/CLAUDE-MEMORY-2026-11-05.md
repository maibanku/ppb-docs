# Claude Code 记忆归档与工作台快照（2026-11-05）

> 来源：`~/.claude/projects/-Users-pipi-ban-Desktop-code-vscode/memory/`（17 个文件全量归档于
> `agent/claude-memory/`，本文件为策展索引与未竟事项快照）。归档后 Claude 会话与
> 记忆存储已按指令清空——新会话不再自动加载任何记忆，接续工作以本文件 +
> `agent/claude-memory/` + 各仓 git 状态为事实源。需要恢复自动记忆时，把
> `agent/claude-memory/*.md` 复制回上述路径并重建 `MEMORY.md` 索引即可。

## 一、工作区布局与运行手册

- **仓库**：`ppb-base`（Go 五服务网关 + iam-web/manage 前端）、`ppb-chat`（chat-desktop
  Tauri 客户端，分支 feat/r1-ux）、`ppb-camera`（XcodeGen+SwiftPM iOS）、`ppb-wardrobe`
  （iOS + 管理端）、`ppb-docs`（本仓）。姐妹检出 `ppb-chat-wt-d`（历史 worktree）。
- **本机启动**：go 在 `~/sdk/go1.26.0/bin`；`ppb-base/deploy` 起六进程（网关 8080 / IAM
  9117）；前端矩阵 base 8210 / chat 8220 / camera 8230 / iam-web dev 8240；桌面端
  `cd chat-desktop && npm run tauri dev`（端口 1420 strictPort）。代理会劫持
  127.0.0.1——跑前清 `HTTP(S)_PROXY/ALL_PROXY` 或设 NO_PROXY。Rust 工具链必须
  `PATH=$HOME/.cargo/bin:$PATH`（homebrew 1.68 撑不起 tauri2/keyring4）。
- 详见 `claude-memory/runbook-local-mac.md`、`ppb-web-frontends.md`。

## 二、各项目当前态（截至 2026-11-05）

| 项目 | 状态 | 关键事实 |
|---|---|---|
| ppb-chat | feat/r1-ux **已 push**，与 origin 同步 | 认证窗口+登录重构已落远端（55818391）：320×360 圆角小窗/QQ 风登录/无勾选默认保存密码+自动登录。测试基线 vitest 686 / cargo 137 |
| ppb-base | main **领先远端 1 提交**（699e8fa 未 push） | iam-web 门户卡片定宽 `width:400px`（去 min）；三页 /login /register /forgot 实测本就同宽，差异感来自与桌面 320px 窗对比 |
| ppb-camera | 执行计划 T00-T25 推进中 | 真机签名已配（个人 Team VKN28YK9M7）；XcodeGen regen 会丢 Team 需重选 |
| ppb-wardrobe | 稳定 | wardrobe-ios-app（含 WardrobeCore）/ manage-web；验证三板斧见记忆 |
| 统一用户中心 | 裁决：不是 SSO、不合并用户 | 4 套身份体系指认 + 治理红线；AdminShell 双模式与 IAM 业务桥已完工（ppb-base 侧） |

## 三、未竟事项（按价值排序）

1. **钥匙串写移出登录响应路径**（ppb-chat，进行到一半）：dev 未签名构建登录时
   macOS 钥匙串授权弹窗阻塞登录 IPC → 前端 20s 超时误报、原生会话可能已建立。
   已完成并测试通过：`SecretExecutor`（内联默认/后台可切）+ epoch 改 `Arc<AtomicU64>`
   基建；未完成：RED 测试三条（响应先返回/epoch 竞速作废/邮箱链）+ 登录路径切
   后台 + lib.rs 接线。**已 stash**：`git stash list` 见 "wip: 钥匙串写移出登录响应
   路径"，恢复 `git stash pop` 后按此清单继续。
2. **ppb-base main 推送**：699e8fa（门户定宽）待 push。
3. friendCtxMenu.test.ts 间歇抖动根治（已证与改动无关的既有问题；stash 基线复验过）。
4. macOS dmg 打包验证窗口改动（透明+macOSPrivateApi 的签名链路）；上架 App Store
   才需回退圆角（直发 DMG/公证无碍）。
5. dev 钥匙串读取路径（try_autologin 的 token 读、登录时 saved-password 读）也可能
   弹窗——写路径修完后如仍有超时感再评估加 timeout。

## 四、方法论沉淀（踩坑速查）

- **GORM**：零值+default 省略列伪装默认值、闭包内自身短声明、`check` 标签、双方言
  锁、成功信封（gorm-pitfalls.md）
- **Tauri/macOS**：透明窗口必须 `transparent:true`+`app.macOSPrivateApi:true`+Cargo
  feature `macos-private-api`；beta 系统整窗透明不绘制但微角透明 OK；Tauri 带 State
  的 async 命令必须返回 Result；flex 卡片内 `margin-top:auto` 只对卡片直接子级生效
- **GUI 驱动回归**：Read 工具图像通道失效时用 mac-gui-drive 技能（ocr.swift 文本锚定
  + px.swift 像素采样 + Chromium CDP 量 DOM）；OCR 子串陷阱/IME 抢焦点/前台窗口
  验证等教训见技能文档
- **跨会话并行**：无 Agent 工具时 SendMessage 任务书派发 + 回执复验（cross-session-
  dispatch-mode.md）；MaxKey/IdP 选型结论：Casdoor>ZITADEL>Keycloak>MaxKey（CVE
  9.8、issue 幻觉教训）
- **存储建模**：字段化 vs KV 的判据（ppb-base/.claude/rules/storage-modeling.md）

## 五、已删除的悬空记忆（历史丢失，不可恢复）

subagent-dispatch、superpowers-trigger-boundary、ppb-crossbiz-authz 三条原文件在
归档前已丢失（索引残留标题）。crossbiz-authz 的 migrate-user 加固即 start-all 契约
漂移来源（见 runbook）；需要时按标题线索重写。
