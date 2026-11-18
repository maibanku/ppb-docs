# P0 基线证据（2026-11-18）

本文件为 P0 只读基线录制的原始证据。所有命令在 2026-11-18 15:41–15:50（UTC+8）执行于本机（macOS, arm64）。未修改任何代码、模块或仓库；仅本 worktree 文档变更。每仓 SHA、运行 PID 均为当场实测，不引用旧快照。

## 1. 工具基线

| 工具 | 版本（实测） | 路径／备注 |
|---|---|---|
| Go | go1.26.0 darwin/arm64 | `/Users/pipi-ban/sdk/go1.26.0/bin/go`；与 go.work/go.mod 声明的 `go 1.26.0` 一致 |
| Node（Homebrew） | v25.2.1 | `/opt/homebrew/bin/node` |
| Node（nvm default=24） | v24.21.0 | `~/.nvm/versions/node/v24.21.0/bin`；nvm 另有 v20.20.1 |
| npm（随 Homebrew node） | 11.6.2 | 需 node 在 PATH（npm 为 env shebang 脚本） |
| npm（随 nvm v24.21.0） | 11.19.0 | 同上 |
| npm（随 nvm v20.20.1） | 10.8.2 | 同上 |
| pnpm | 10.28.2 | `/opt/homebrew/bin/pnpm`，需 node 在 PATH |
| rustc | 1.99.1 (58cf8f9c3 2026-10-13) | `$HOME/.cargo/bin/rustc` |
| cargo | 1.99.1 (5f94df478 2026-08-27) | `$HOME/.cargo/bin/cargo`；rustup 1.29.3 |
| Java | OpenJDK 17.0.17 LTS（Zulu17.62+17-CA, build 17.0.17+10-LTS） | `/opt/homebrew/opt/openjdk@17`（.zshrc 注入） |
| CocoaPods | 1.17.0 | `/opt/homebrew/bin/pod`（需 LANG=UTF-8，否则告警） |
| Xcode | 27.1 (Build 27A9275)；Swift 6.4 (swiftlang-6.4.0.34.1) | `xcodebuild -version` |
| git | 2.54.0 (Apple Git-157) | 系统默认 |
| gh | 未安装 | `gh` 不在 PATH，`/opt/homebrew/bin/gh` 不存在；GitHub 侧核对用 `git ls-remote` 替代 |

PATH 缺口（对后续阶段的提示）：非交互 shell 中 `go`、`node`、`npm`、`pod` 均不在默认 PATH；`.zshrc` 第 23 行注入的 `/usr/local/opt/node/bin` 在本机（ARM Homebrew）不存在，属陈旧 Intel 路径。启动 `deploy/scripts/start-all.sh` 的桌面会话环境另有 PATH 注入（15:39 构建成功可证 go 可用）。Rust 一律走 `$HOME/.cargo/bin`（与既有记忆一致：Homebrew cargo 1.68.1 读不懂 lock v4）。

## 2. 仓库状态登记（实测于 15:41–15:44）

父目录 `/Users/pipi-ban/Desktop/code/vscode/`。dirty 计数 = `git status --porcelain` 非 `??` 行数；ahead/behind = `git rev-list --left-right --count @{u}...HEAD`（左 behind 右 ahead）。

| 仓库 | 分支 | HEAD SHA | dirty | untracked | behind/ahead | 远端 |
|---|---|---|---|---|---|---|
| ppb-docs | main | `00df2c5481457a7268b0facf49911564039a89a0` | 0 | 1（`worktrees/`，即本 worktree 目录本身） | 0/0 | git@github.com:maibanku/ppb-docs.git |
| ppb-base | main | `97dd8b072358c13f160ab114644450196dfda411` | 0 | 0 | 0/0 | git@github.com:maibanku/ppb-base.git |
| ppb-chat | main | `de417bb8e266952ad30ffaf74cd01d326d6e4527` | 0 | 0 | 0/0 | git@github.com:maibanku/ppb-chat.git |
| ppb-camera | main | `dfdfd3c9aab44abb6789bf95d6c820371b29e33b` | 0 | 0 | 0/0 | **https**://github.com/maibanku/ppb-camera.git（其余四仓均 SSH） |
| ppb-wardrobe | main | main `33e07cff0fa7315c9aec0f3096b7bf084669fc62` | 0 | 0 | 0/0 | git@github.com:maibanku/ppb-wardrobe.git |

五仓全部：分支 main、与 origin/main 零偏离（本地即远端最新）、工作区干净。ppb-docs 的 00-现状文档旧快照（ppb-base d9d13650、ppb-chat a2520836）已被推进：ppb-chat 现为 de417bb8（mobile 批次7 收口 merge），ppb-base 现为 97dd8b0（W7）。

worktree 登记（`git worktree list`）：

- ppb-docs：主检出 `…/vscode/ppb-docs` [main] + `…/vscode/ppb-docs/worktrees/p0-layout` [refactor/ppb-repository-layout] @00df2c5（本任务 worktree）。
- ppb-base / ppb-chat / ppb-camera / ppb-wardrobe：仅主检出，无任何注册 worktree。

计划外资产登记（不改动）：

- `vscode/infra/`：非 git 仓库（`git rev-parse` fatal）。含 docker-compose.yml（MySQL 8.0 容器 ppb-mysql:3306、Redis 7 容器 ppb-redis:6379）、launchd 常驻 MinIO(9000/9001，数据在 ppb-base/deploy/data/minio)、infra.sh、backups/（MySQL 全量备份保留 10 份）、logs/、`.env` 凭据。
- `ppb-chat/PATHFINDER-2026-11-17/`：**已提交入库**（`git ls-files` 命中 00-features.md、01-flowcharts/*、02-duplication-report.md、03-unified-proposal.md、04-handoff-prompts.md），非 untracked。
- `ppb-chat/node_modules/`：`.gitignore:6` `/node_modules/` 忽略。
- ppb-chat 存在空目录 `worktrees/`（无注册项）；ppb-base 无 worktrees 目录。
- `ppb-base/deploy/bin/` 内有多份历史备份二进制（gateway.previous-*、gateway.thin-next、im.friends-next 等，10/28–11/12）与 `deploy/run/` 内陈旧 pid（`file 2.pid`、`gateway 2.pid`/`gateway 3.pid`、`iam 2.pid`、`im 2.pid`/`im 3.pid`）；`plugin.pid` 内容为 0（plugin 进程未运行，二进制停于 10/27）。`deploy/data/` 另有陈旧库文件（ppb_user.db、im.db、user.db、stale-gencol-preT8-20261105 系列、`ppb_im.db?mode=ro` 异名文件）。均登记不动，清理留待后续阶段决策。

目标新仓存在状态：`ppb-iam`、`ppb-gateway`、`ppb-file` 本地不存在；远端 `git ls-remote git@github.com:maibanku/<r>.git` 三仓均 `Repository not found`（SSH 凭据有效已由 ls-remote maibanku/ppb-base 返回 HEAD=97dd8b0 反证）→ 截至 2026-11-18 15:44 远端亦不存在，创建属后续阶段。

## 3. Go 模块清单

`ppb-base/go.work`（实测内容）：`go 1.26.0`，use 六模块 `./server-camera ./server-file ./server-gateway ./server-iam ./server-im ./server-pkg` —— 六模块形态与 00 文档一致，确认。

| 模块目录 | module 路径（go.mod 首行实测） | go 声明 | replace |
|---|---|---|---|
| server-camera | github.com/ppbchat/server-camera | 1.26.0 | server-pkg => ../server-pkg |
| server-file | github.com/ppbchat/server-file | 1.26.0 | server-pkg => ../server-pkg |
| server-gateway | github.com/ppbchat/server-gateway | 1.26.0 | server-pkg => ../server-pkg |
| server-iam | github.com/ppbchat/server-iam | 1.26.0 | server-pkg => ../server-pkg |
| server-im | github.com/ppbchat/server-im | 1.26.0 | server-pkg => ../server-pkg |
| server-pkg | github.com/ppbchat/server-pkg | 1.26.0 | —（被以上五仓 replace 引用） |

其余仓库：ppb-wardrobe 有独立模块 `wardrobe-manage-web/server/go.mod`；ppb-chat、ppb-camera 顶层两层内无 go.mod（纯前端/客户端仓）。

## 4. 运行基线（2026-11-18 15:39 重启，实测）

启动脚本 `ppb-base/deploy/scripts/start-all.sh`：顺序 build → migrate(im/iam) → im → file → iam → gateway；健康探测 im 9112 /healthz、file 9114 /ping、iam 9117 /ping、gateway 8080 /ping；构建采用临时文件逐字节比对再原子替换（mtime 判旧幂等）。本轮全部二进制 mtime 2026-11-18 15:38–15:39，ppb-base 工作区干净且 HEAD=97dd8b0 → **五个服务进程均运行自 ppb-base main `97dd8b0` 的源码构建**。

| 服务 | PID | 启动时刻（ps lstart） | 监听端口（lsof 实测） | 配置 |
|---|---|---|---|---|
| im | 38568 | 15:39:08 | 9102、9112 | deploy/bin/im |
| file | 38609 | 15:39:10 | 9104、9114(127.0.0.1) | deploy/config/file.yaml |
| iam | 38644 | 15:39:12 | 9107、9117 | deploy/bin/iam |
| camera | 38893 | 15:39:35 | 9106、9116 | server-camera/config.yaml |
| gateway | 38932 | 15:39:38 | **8080** | deploy/config/gateway.yaml + gateway-routes.yaml |

网关探活实测：`curl http://127.0.0.1:8080/ping` → HTTP 200，`{"data":null,"code":0,"success":true,"message":"ok"}`。gateway.log 尾部可见 15:39:38「透明网关启动 … HTTP 服务开始监听 0.0.0.0:8080」，路由文件 deploy/config/gateway-routes.yaml。plugin 进程未运行（plugin.pid=0）。

数据面实测：

- **运行库为 SQLite**：lsof 证实 pid 38568 持有 `deploy/data/ppb_im.db(-shm/-wal)`、pid 38644 持有 `ppb_iam.db(-shm/-wal)`；im 无 3306 连接。各 config 的 dsn 均为空（回落 SQLite 起步态），deploy/db.env 存在（键：PPB_DB_HOST/USER/PASSWORD、PPB_REDIS_ADDR、PPB_SMTP_*、PPB_MQ_URL）但本轮启动未把服务切到 MySQL。
- infra 依赖：MySQL 8.0 容器 Up 2 days (healthy)、Redis 7 容器 Up 2 days (healthy)、MinIO launchd ok（infra.sh 探活 3/3 ok）。本机 LAN IP 即 192.168.3.55（im.yaml redis addr=192.168.3.55:6379 指向本机容器映射）。
- 迁移：`deploy/sql/ppb_im/incremental/20261118_01_group_notice_updated_at.sql` 在 start-all 流程内（migrate-im 二进制 15:39 同步重建）；只读核验 `PRAGMA table_info(im_group)` 第 11 列 `notice_updated_at datetime` **已在运行库 ppb_im.db 存在**（该脚本 ALTER 的是 `im_group` 表，非独立 group_notice 表）。migrate-file 二进制停于 10/28（start-all 只 migrate im/iam）。

## 5. 已知缺口／阻塞登记

| # | 类别 | 事实（证据） | 影响／后续 |
|---|---|---|---|
| G1 | 验收未执行 | W7 后端已上线，但 notice_updated_at 线面回执（GET /im/groups/{id}/members 的 noticeUpdatedAtUnix）与 peerUserId 字段**未做运行时验证**——本 P0 仅证到 DB 列存在 | 深度字段验证未执行，待专项回归（对应 ARC-21 基线输入，非通过项） |
| G2 | 并行会话风险 | 控制方通报桌面会话活跃于 ppb-b8-* worktree 并推送 ppb-chat/ppb-base 的 origin/main。实测 15:44：`find …/vscode -maxdepth 2 -name 'ppb-b8-*'` 无命中；ppb-chat/worktrees 为空目录；ppb-base 无 worktrees；五仓 0 dirty、0/0 偏离。桌面会话痕迹当下不可见（已清理或暂歇），但视为持续在场风险——任何写仓操作前须重新对账 HEAD | 后续每阶段开头重新枚举 worktree/HEAD |
| G3 | 计划外资产 | infra/（docker-compose+backups+logs，非 git 仓）未纳入迁移计划管理；MySQL 本轮未被服务使用但健康在跑 | 后续阶段决定是否纳管/登记 |
| G4 | MQ 缺位 | im 进程持续告警 `eventmq: 消费连接失败 dial tcp 192.168.3.55:5672: connection refused`（15:39–15:45+ 每 5s 重试）；RabbitMQ 不在 infra 服务清单（仅 mysql/redis/minio），PPB_MQ_URL 指向的 5672 无监听 | 运行基线含 MQ 断连；事件链路验收（ARC-25 相关）前需部署或显式标记可选 |
| G5 | 工具链 PATH | 非交互 PATH 无 go/node/npm/pod；.zshrc 残留 Intel 路径 /usr/local/opt/node/bin；gh 未安装 | 自动化脚本需显式 PATH（go=/Users/pipi-ban/sdk/go1.26.0/bin、cargo=$HOME/.cargo/bin）；GitHub 操作走 git SSH |
| G6 | 杂项残留 | deploy/bin 历史备份二进制 8 份、run/ 陈旧 pid 6 个、plugin 未运行、data/ 陈旧库文件若干；ppb-camera remote 为 https 与其余仓不一致 | 登记不动；清理留待后续阶段单独提交 |

## 6. 结论

P0 六项交付（工具、仓库、模块、运行态、缺口登记、检查点提交）全部完成，证据如上。未发布任何 Go/npm/镜像版本；未执行任何 DDL 写入（PRAGMA/lsof 均只读）；未改动五仓任何源码。
