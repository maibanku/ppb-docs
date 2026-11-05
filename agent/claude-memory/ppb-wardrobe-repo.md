---
name: ppb-wardrobe
description: AI 衣柜仓库结构（wardrobe-ios-app / wardrobe-manage-web 根目录布局、xcodeproj 生成契约、验证命令）
metadata:
  node_type: memory
  type: project
---

AI 衣柜仓库（GitHub maibanku/ppb-wardrobe）。2026-11-02 结构重组（用户拍板，曾有一次仅移 apps/ios 的方案被回滚后改为全量）：

- `wardrobe-ios-app/`：苹果端全部代码 = Wardrobe 源码 + Wardrobe.xcodeproj + WardrobeCore（SwiftPM 包+测试，自 packages/ 迁入）。包相对路径 relativePath="WardrobeCore"（相对 xcodeproj 所在目录）。
- `wardrobe-manage-web/`：后台（运营）前端文档/代码，原 apps/web/admin 迁入（用户原文拼写 managet，经确认改用 manage）。`apps/web/` 只剩 personal 个人端。services/、contracts/ 未动。
- **xcodeproj 是生成物**：`scripts/generate_xcode_project.py` 硬编码 `IOS = ROOT/"wardrobe-ios-app"` 与 relativePath；`scripts/check_structure.py` 校验生成物一致性、全仓 markdown 链接、Core 只 import Foundation 等红线。增删/移动 Swift 文件后必须 regenerate，不手改 pbxproj。改 md 链接注意 apps/web 距根两层（../../）。
- 验证三板斧（2026-11-02 本机全绿）：`python3 scripts/check_structure.py`；`swift test --package-path wardrobe-ios-app/WardrobeCore --scratch-path /tmp/...`（Desktop iCloud codesign 坑见 [[runbook-local-mac]]）；`xcodebuild -project wardrobe-ios-app/Wardrobe.xcodeproj -scheme Wardrobe -sdk iphonesimulator -derivedDataPath /tmp/... CODE_SIGNING_ALLOWED=NO build`。Core 14 测试。
- CI：.github/workflows/ios.yml 路径已同步（macOS runner 跑上述三步）。

2026-11-02 全量实现轮（用户四裁决：P0全量+P1可落地 / personal 并入 manage-web 双前端 / Go+GORM+MySQL 后端放 wardrobe-manage-web/server / Vue3+Vite）：主计划在仓内 `.superpowers/plans/2026-11-02-wardrobe-full-buildout.md`（12 片、跨片契约冻结：同步协议v1/任务v1/鉴权v1、端口 server 8270/personal 8271/admin 8272、库名 wardrobe）。agent team 波次：`[2∥5]→[3∥4∥6]→[7∥8∥9]→[10∥11]→[12]`；实现 agent 走预建 worktree（`.claude/worktrees/sN-*`，主会话复验后 ff 合并）——两个 agent 同时让 Agent 工具自建 worktree 会撞 .git/config 锁，**先 git worktree add 预建再派发**。进度：S0/S1 已并 main（0624b6c/6be1f86，根只剩两目录+.github+.superpowers，scripts/docs 移入 wardrobe-ios-app）；S2 已并 main（7c9f168，Core 68 测试：WearLedger/ChangeLog 墓碑/ExportPackager sha256/Avatar 参数分域+模板目录、纯 Swift SHA256 保持零依赖）；S3（iOS 穿着/设置/删除完整性）与 S5（Go 同步 API）进行中。2026-11-03 深夜全量实现轮收官：main=`ce1f909`，12/12 片完成（S0 结构收口→S2 Core 领域→S3 穿着/设置→S4 拍照拆分→S5/S6 Go 同步+任务编排→S7 iOS 同步→S8/S9 Web 双前端→S10 3D 形象→S11 VTON→S12 验证轮）。四端测试 460/0（Core 194、server 73 真MySQL、personal 117、admin 76）+iOS 真后端冒烟 29/29。验收记录在 `.superpowers/acceptance/2026-11-03-{验收执行记录,需求覆盖对照}.md`：REQ 41 通过/13 未执行/1 阻塞（NFR-01 需真模型）；发布门槛按 ac 严格口径判「暂缓」，缺口 D-1~D-7（真模型评估、设备性能基准冻结、端侧模型包管理、产物回退演练、AVA-05 偏好联动、运营告警、iOS UI 测试债）。注意：验收文档引用外部仓 ppb-docs 用纯文本不用 md 链接（出仓相对链接会被 check_structure 拦且 worktree 深度不同）。未 push（origin/main 落后 20+ 提交）。

参考其他 ppb 代码（用户要求）：Go 参考 ppb-base/server-{file,iam,gateway,camera,pkg}（go.work 仓）；Vue 参考 base-manage-web 与 file/iam/platform-manage-web、chat-manage-web；iOS 参考 ppb-camera/camera-ios-app（IAMAccountSection 账号 UI、SessionContinuation）。

**worktree 协议教训（两起事故后固化）**：① agent 任务书首行必须「先 cd 绝对路径」，否则 agent 早期会把草稿误写进主树（S6 的 tasks_admin.go 旧草稿卡了 merge——收片遇 untracked 挡道时，`git show 分支:路径 | diff - 主树文件` 确认是旧草稿再删）；② 主会话每条 git 命令都要绝对 cd 前缀——shell cwd 会漂（曾因此在 worktree 里跑 merge 白合并、删 worktree 时 cwd 在其内导致链断）；③ Desktop iCloud 抖动：偶发 No such file，重试即恢复。

S7（iOS 同步+账号，2026-11-03 凌晨，worktree s7-ios 提交 93db29b 待并）：引擎下沉 WardrobeCore/Application/Sync（SyncWire 信封/wire 编解码、SyncEngine actor 状态机+幂等键+冲突/合并、RemoteChangeApplier pull 折叠、SyncState 随快照持久化），App 侧只留 APIClient（Keychain token）+WardrobeSyncService 适配器薄壳（xcodeproj 生成器不支持 test target → Core 测试 159 条）。要点：登录≠上传（per-account consent 键）；存储 Spaces/guest|account-<id> 隔离+旧布局一次性迁入 guest；ChangeLog 语义定稿（removeOps(matching:) 精确删已确认、recordRemoteTombstone 不回推、prune 连已合并 delete 一起删）；冲突 keepLocal 必须重传**队列里那条 op 的 payload**（真冒烟抓到的 bug：pull 可能已把 live entity 换成服务端版）。真 server 冒烟法：/tmp 建 SwiftPM exe 以 path 依赖 symlink WardrobeCore，跑真 SyncEngine 对 127.0.0.1:8270（DB wardrobe_smoke_s7）。
