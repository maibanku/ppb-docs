# PPB 架构改造实施进度

## 当前检查点

日期为 2026-11-18。P0 基线、P1 基础模块提取（P1a 盘点／P1b 轻量五包／P1c 四适配模块+两死包退役）与三新仓拆分（ppb-iam／ppb-gateway／ppb-file）已实施；P1 独立评审在途。公共模块尚未打 tag 发布，三新仓仅存本地分支，远端仓未创建（缺口 G7）。

| 阶段 | 状态 | 当前证据 |
|---|---|---|
| 文档与静态分析 | 文档已编写 | architecture 目录及现有入口更新 |
| P0 本地工具／运行基线 | 已执行 | [P0 证据](p0-evidence.md)：工具/五仓 SHA/六模块/15:39 运行态实测 |
| P1 框架与适配 | 实施完成，评审在途 | worktree p1-framework：925fd32（P1b）+ 9e9c478..ff88bbe（P1c）；11 模块 66 ok/0 fail |
| P2 契约与 SDK | 待执行 | 远程版本尚未发布（前置：go-framework 打 tag） |
| P3 网关独立仓 | 目标仓已建（本地） | ppb-gateway/service-gateway 独立构建全绿；原仓移除与部署切换未做 |
| P4 前端公共包 | 待执行 | 新仓前端经 file:／相对路径桥接至 ppb-base（临时，见各仓 MIGRATION.md） |
| P5 IAM 独立仓 | 目标仓已建（本地） | ppb-iam/service-iam 独立构建全绿；原仓移除与部署切换未做 |
| P6 Camera 后端 | 待执行 | 目标 ppb-camera/service-camera |
| P7 IM 与 File | File 仓已建（本地）；IM 未动 | ppb-file/service-file 独立构建全绿 |
| P8 独立构建／集成／回退 | 待执行 | 待生成实际制品与证据 |

## 下一次启动

P1 评审收口后进入 P2：grpc_gen/user-compat/refaccess 契约拆分与 platform-sdk（先给 go-framework 及嵌套适配模块打 tag，再撤 replace 切远程版本）。并行待办：① 用户 `gh auth login` 或网页建私有空仓 maibanku/ppb-iam、ppb-gateway、ppb-file，随后三新仓设 origin 并推 refactor/ppb-repository-layout（缺口 G7）；② 原仓移除与部署引用切换按 P8 序（目标仓独立回归后）。开工前重新对账各仓 HEAD（缺口 G2）。

## 仓库状态登记（P0 实测 2026-11-18 15:41–15:44）

| 仓库 | 分支 | 起点 SHA | 最新已提交 SHA | 工作区／依赖状态 |
|---|---|---|---|---|
| ppb-docs | main（另有 worktree refactor/ppb-repository-layout） | 53abba76（00 文档快照） | 00df2c5481457a7268b0facf49911564039a89a0 | 干净；untracked 仅 worktrees/；与 origin/main 0/0 |
| ppb-base | main | d9d13650（00 文档快照） | 97dd8b072358c13f160ab114644450196dfda411（W7） | 主检出干净 0/0，运行态即此 SHA 构建；另有 worktree p1-framework（refactor/ppb-repository-layout @ ff88bbe，P1 实施线） |
| ppb-iam | refactor/ppb-repository-layout（本地，未推送） | filter-repo 自 ppb-base main@97dd8b0 | a95f6a3（拆仓基点 9cec7ca4 + 6 迁移提交） | 新仓：service-iam/iam-web/iam-manage-web + deploy/sql/ppb_iam + deploy/config/iam.yaml，196 commits 历史保留；树干净；远端不存在（G7） |
| ppb-gateway | refactor/ppb-repository-layout（本地，未推送） | filter-repo 自 ppb-base main@97dd8b0 | 7445815（拆仓基点 f0802888 + 3 迁移提交） | 新仓：service-gateway + deploy/config/gateway*.yaml，158 commits；树干净；远端不存在（G7） |
| ppb-file | refactor/ppb-repository-layout（本地，未推送） | filter-repo 自 ppb-base main@97dd8b0 | 1a56c3e（拆仓基点 bcb78b54 + 4 迁移提交） | 新仓：service-file/file-manage-web + deploy/sql/ppb_file + deploy/config/file*.yaml，78 commits（剔除运行库 ppb_file.db）；树干净；远端不存在（G7） |
| ppb-chat | main | a2520836（00 文档快照） | de417bb8e266952ad30ffaf74cd01d326d6e4527（mobile 批次7） | 干净 0/0；PATHFINDER-2026-11-17/ 已提交入库；node_modules 已忽略 |
| ppb-camera | main | dfdfd3c9 | dfdfd3c9aab44abb6789bf95d6c820371b29e33b（未推进） | 干净 0/0；remote 为 https 与其余仓不一致 |
| ppb-wardrobe | main | 33e07cf | 33e07cff0fa7315c9aec0f3096b7bf084669fc62（未推进） | 干净 0/0 |

计划外资产登记（不动）：vscode/infra/（docker-compose MySQL/Redis + launchd MinIO + backups，非 git 仓）、ppb-chat/PATHFINDER-2026-11-17/（已提交）、ppb-chat/node_modules/（忽略）、ppb-base deploy/bin 历史备份二进制与 deploy/run 陈旧 pid、deploy/data 陈旧库文件。明细见证据第 2 节。

## 每次检查点格式

### 日期与阶段

- 本次目标及对应验收编号
- 修改的仓库、分支、文件和提交
- 实际执行命令及输出摘要
- 运行结果，使用通过、失败、未执行、待后续阶段
- 发布的 Go／npm／镜像／路由版本及摘要
- 数据、协议、权限与旧路径兼容状态
- 已知缺口、具体阻塞和可继续执行的工作
- 回退依据及下一步

按此格式追加新检查点小节；记录最后一组提交时避免在当前提交中递归填写自己的 SHA，可在阶段报告或下一次检查点记录。

## 检查点记录

### P0（2026-11-18，基线录制）

- 本次目标：P0 工具/仓库/模块/运行态基线，为 ARC-21（schema 基线输入）及各阶段起点提供事实；只读，不改代码。对应执行提示词 P0 节。
- 修改：仅 ppb-docs worktree refactor/ppb-repository-layout 两份文件——本文件与新增 [p0-evidence.md](p0-evidence.md)。五业务仓零改动。
- 命令与输出摘要：工具版本探测（go1.26.0 darwin/arm64、node v25.2.1/nvm24 v24.21.0、rustc 1.99.1、Zulu 17.0.17、pod 1.17.0、Xcode 27.1、git 2.54.0）；五仓 `rev-parse HEAD`/`status --porcelain`/`rev-list --left-right --count @{u}...HEAD`/`worktree list`；`ls-remote` 证三目标仓远端不存在；go.work 与六 go.mod 读取；15:39 运行态 `ps`/`lsof` 端口与 DB 文件、`curl 127.0.0.1:8080/ping`→200、`PRAGMA table_info(im_group)`。全量原始输出见证据文件。
- 运行结果：网关 /ping 通过；五服务进程存活通过；迁移列 im_group.notice_updated_at 在运行库存在（只读核验）通过；notice_updated_at／peerUserId 线面验证**未执行**；RabbitMQ 连接失败（持续重试中，登记为运行态既存缺口）。
- 发布版本：无（P0 不发布任何 Go/npm/镜像/路由版本）。
- 数据/协议/权限/旧路径：全部保持原样；无 DDL 写入、无数据迁移、无接口调用副作用（仅 /ping 与只读 PRAGMA/lsof）。
- 已知缺口与阻塞：见证据第 5 节 G1–G6（W7 深度验证未执行、并行会话风险、infra 未纳管、MQ 缺位、PATH 缺口、杂项残留）。无阻塞 P1 的硬障碍。
- 回退依据与下一步：本检查点纯文档，回退即 revert 该提交。下一步 P1：server-pkg 轻量包与适配模块提取（go-framework 落位），开工前重新对账各仓 HEAD（缺口 G2）。

### P1 提取与三仓拆分（2026-11-18，16:20–17:40）

- 本次目标：P1 基础模块提取（执行提示词 P1 节）+ 用户指令「创建新目录 file iam gateway 按照文档迁移改造项目」→ ppb-iam／ppb-gateway／ppb-file 三仓拆分落地。
- 修改的仓库、分支与提交：
  - ppb-base worktree p1-framework（refactor/ppb-repository-layout）：P1b `925fd32`（logx/requestid/idstr/health/errcode 纯段上收 go-framework + server-pkg 垫片）；P1c `9e9c478`（snowflake 联动上收）、`26412ad` rpcx、`80dd944` gormx、`3626d45` mq/rabbitmq、`8ad914c` messaging/kafka、`dc74553`/`ff88bbe`（outbox、cache 死包退役）。五服务 go.mod/源码零改动；主检出与运行态零触碰。
  - 三新仓均经 `python3 -m git_filter_repo` 路径过滤自 ppb-base main@97dd8b0（历史保留，路径映射见各仓 docs/MIGRATION.md），分支 refactor/ppb-repository-layout。ppb-iam：`8c46e38`（module 更名 maibanku/ppb-iam/service-iam + 153 处 import 重写 + replace 桥接）、`6b36419`/`c10e52a`（前端 file: 依赖、vite 别名、vendor 门面、iam-web 源码 import 四层桥接至 ../../ppb-base）、`3df1217`/`9b3baf9`（仓根文件与守卫收敛）、`a95f6a3`（退役入库二进制 server+migrate 共 61MB）。ppb-gateway：`08ed31d`（module 更名 + tidy 收敛）、`102312d`、`7445815`（退役 37.6MB 入库二进制 deploy/bin/gateway）。ppb-file：`659105a`（module 更名 + 55 处 import）、`4851785`（前端四层桥接）、`5ab0e78`、`1a56c3e`。
- 实际执行命令及结果：P1 线各新模块 `GOWORK=off go mod download/build/test/vet ./...` 全过，工作区 11 模块 `go build+test` **66 ok／0 FAIL**（基线 68，差 2 为退役死包自身测试）。三新仓 `GOWORK=off go build ./... && go test ./...`：iam **9 ok**、gateway **3 ok**、file **6 ok**，0 FAIL（go1.26.0，GOPROXY=goproxy.cn,direct，控制器本机复跑确认）。前端：file-manage-web typecheck 过 + vitest 12 tests 过；iam 双前端 typecheck **零诊断**（node 24.21.0）。守卫：三仓 grep 与 `git grep HEAD` 旧 module 全路径 **0 命中**。流程：每仓独立实施（subagent）→ 独立验收（subagent）→ 修复轮（iam 补 vite 别名/vendor/源码 import 桥接、gateway/iam 二进制退役、MIGRATION 守卫归零）→ 控制器终验。
- 发布版本：无。module 更名 `github.com/maibanku/ppb-{iam,gateway,file}/service-*` 已落；公共库经 `replace github.com/ppbchat/server-pkg => ../../ppb-base/server-pkg` 本地桥接（P2 打 tag 后切远程版本，各仓 go.mod 有注释标记）。
- 数据、协议、权限与旧路径兼容：wire 面零改动——.go 变更逐 hunk 验收为**纯 import 行**（非 import 行 0）；protobuf package／字段编号／数据库／配置文件路径全保持；运行态进程与数据库零触碰。
- 已知缺口、阻塞与可继续工作：**G7** gh CLI 已装未登录（token 认证需用户 `gh auth login`，或网页建私有空仓 maibanku/ppb-{iam,gateway,file}），三新仓未设远端未推送；G4 RabbitMQ 未部署沿用；前端 typecheck 须 **node 24.x**（homebrew node 25.2.1 下 vue-tsc 出 33+47 条伪影错误，24.21.0 下零诊断——CI 应锁版本）；ppb_user*.sql／seed_menus.sql／00-create-databases.sql／deploy/docker/Dockerfile.service／tools/gen-routes 留守 ppb-base（P2/P4/P8 裁决）；原仓移除与部署引用切换未做（P8 序）；P1 独立评审在途（结论落地后补记）。可继续：P2 契约/SDK、前端构建产物链验证（npm run build 未跑，仅 typecheck/vitest）。
- 回退依据与下一步：三新仓为独立目录，删除即回退；ppb-base 主检出/运行态零改动；P1 线独立 worktree 可整线 revert。下一步：P1 评审收口 → P2（grpc_gen/user-compat/refaccess 契约 + platform-sdk/iam、file 客户端）→ tag 发布与 replace 切换 → 远端建仓推送（G7 解除后）。
