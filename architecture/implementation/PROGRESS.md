# PPB 架构改造实施进度

## 当前检查点

日期为 2026-11-18。P0 基线录制完成，证据见 [p0-evidence.md](p0-evidence.md)，提交在 ppb-docs 分支 refactor/ppb-repository-layout。此状态不代表任何新服务仓、公共版本或运行环境已就绪。

| 阶段 | 状态 | 当前证据 |
|---|---|---|
| 文档与静态分析 | 文档已编写 | architecture 目录及现有入口更新 |
| P0 本地工具／运行基线 | 已执行 | [P0 证据](p0-evidence.md)：工具/五仓 SHA/六模块/15:39 运行态实测 |
| P1 框架与适配 | 待执行 | 当前 server-pkg 仍在 ppb-base |
| P2 契约与 SDK | 待执行 | 远程版本尚未发布 |
| P3 网关独立仓 | 待执行 | 目标 ppb-gateway/service-gateway |
| P4 前端公共包 | 待执行 | 当前仍有 file: 和源码别名 |
| P5 IAM 独立仓 | 待执行 | 目标 ppb-iam/service-iam |
| P6 Camera 后端 | 待执行 | 目标 ppb-camera/service-camera |
| P7 IM 与 File | 待执行 | 目标 Chat 和 File 仓 |
| P8 独立构建／集成／回退 | 待执行 | 待生成实际制品与证据 |

## 下一次启动

P0 已收口。下一步执行 P1 基础模块提取：从 ppb-base/server-pkg 迁移 logx、requestid、ID 转换、错误与健康等轻量包及 gRPC/GORM/Redis/RabbitMQ/Outbox 独立适配模块（详见 [执行提示词](CLAUDE_CODE_PROMPT.md)）。开工前重新枚举各仓 HEAD 与 worktree（并行桌面会话可能推进 origin/main，见缺口 G2）；发现目标仓已经创建时采用现状核对，不重复初始化。

## 仓库状态登记（P0 实测 2026-11-18 15:41–15:44）

| 仓库 | 分支 | 起点 SHA | 最新已提交 SHA | 工作区／依赖状态 |
|---|---|---|---|---|
| ppb-docs | main（另有 worktree refactor/ppb-repository-layout） | 53abba76（00 文档快照） | 00df2c5481457a7268b0facf49911564039a89a0 | 干净；untracked 仅 worktrees/；与 origin/main 0/0 |
| ppb-base | main | d9d13650（00 文档快照） | 97dd8b072358c13f160ab114644450196dfda411（W7） | 干净 0/0；运行态即此 SHA 构建；无其他 worktree |
| ppb-iam | 本地与远端均不存在 | — | — | ls-remote maibanku/ppb-iam → Repository not found；创建属后续阶段 |
| ppb-gateway | 本地与远端均不存在 | — | — | 同上 |
| ppb-file | 本地与远端均不存在 | — | — | 同上 |
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
