# PPB 架构改造实施进度

## 当前检查点

日期为 2026-11-18。P0 基线、P1 基础模块提取（P1a 盘点／P1b 轻量五包／P1c 四适配模块+两死包退役）与三新仓拆分（ppb-iam／ppb-gateway／ppb-file）已实施；P1 独立评审在途。公共模块尚未打 tag 发布，三新仓仅存本地分支，远端仓未创建（缺口 G7）。

| 阶段 | 状态 | 当前证据 |
|---|---|---|
| 文档与静态分析 | 文档已编写 | architecture 目录及现有入口更新 |
| P0 本地工具／运行基线 | 已执行 | [P0 证据](p0-evidence.md)：工具/五仓 SHA/六模块/15:39 运行态实测 |
| P1 框架与适配 | 完成（评审 APPROVE_WITH_NITS） | worktree p1-framework：925fd32（P1b）+ 9e9c478..ff88bbe（P1c）+ 8f85abe（M1 gofmt）；11 模块 66 ok/0 fail |
| P2 契约与 SDK | P2a 完成（评审 APPROVE_WITH_NITS）；P2b 实施中 | contracts/{common,iam,file,im,camera,user-compat} 六模块 @ 093928f，buf 真重生成零漂移，17 模块 66 ok；platform-sdk 两模块在途 |
| P3 网关独立仓 | 目标仓已建（本地） | ppb-gateway/service-gateway 独立构建全绿；原仓移除与部署切换未做 |
| P4 前端公共包 | P4a 完成（verify PASS） | base-manage-web 库/演示双产物 + npm pack 消费实证（p4-frontend worktree）；P4b 发布链/插件化待 |
| P5 IAM 独立仓 | 目标仓已建（本地） | ppb-iam/service-iam 独立构建全绿；原仓移除与部署切换未做 |
| P6 Camera 后端 | 目标仓已建（本地） | ppb-camera/service-camera 9 ok（verify PASS）；原仓移除未做 |
| P7 IM 与 File | IM+File 仓均已建（本地） | ppb-chat/service-im 16 ok（verify PASS）；rtc/friendevent 迁移挂 P7b |
| P8 独立构建／集成／回退 | 待执行 | 待生成实际制品与证据 |

并行波次登记（2026-11-18 17:50 起，四线六 agent）：A=P2a 完成→评审+P2b 接续（p1-framework worktree）；B=P7 IM 迁入 ppb-chat（vscode/ppb-chat-wt，分支 refactor/ppb-repository-layout-im）；C=P6 Camera 迁入 ppb-camera（vscode/ppb-camera-wt）；D=P4a base-manage-web 双产物（p4-frontend worktree）。IM/Camera 拆仓统一自冻结基点 97dd8b0；其 worktree 置于 vscode 层使 ../../ppb-base 桥接路径与主检出同深度可验证。

### P2a 契约模块（2026-11-18，worktree p1-framework 8f85abe..093928f）

- 目标：grpc_gen 各域 + user-compat + refaccess → contracts/* 嵌套 module，server-pkg 垫片，descriptor 单注册权威。
- 提交：2247e13/8a5206e/e584677/ba5c9a2/9d3f08e（五域）、8e63584（四域 *_FullMethodName 直通补丁）、7443086（user-compat + buf.gen.yaml 新布局 + endpoint-audit replace 收口）、093928f（p2a-notes + README 生成链路）。
- 证据：**buf v1.74.0 + protoc-gen-go v1.34.2 真工具链重生成**——改 go_package 前基线重生成与库内 15 个 pb.go 逐字节一致；终态全量 buf generate git diff 为空。protobuf package/RPC 全名/字段编号零变化。单注册：全仓显式 Register*=0（隐式注册），rawDesc 仅存 contracts；server-pkg/grpc_gen 七包纯垫片。六模块 GOWORK=off 自洽全过；工作区 17 模块 build+vet 全绿、test 66 ok/0 FAIL（=基线）；五服务零改动。
- 裁决与登记：user-compat 落 contracts 下独立 module（01 目录树与盘点为准，非任务文「iam 下」——兼容模块需可独立移除）。common.proto 24 类型中仅 3 真公共，21 个 IM 线面类型暂驻（明细 docs/p2a-notes.md，归 contracts/im 待后续批）。遗留五项：idl/ proto 文件本体迁 contracts、Mtodo 映射、iamx/user-compat owner 逐项核对、errcode BizError 归位、contracts 发版去 replace。
- 前瞻（P1/P2 线合入 ppb-base main 后）：三新仓需补 contracts 六条 replace（非主模块 replace 不传导，同 endpoint-audit 收口模式）。
- P8 切换面预查：服务编排全在 ppb-base/deploy/docker-compose.yml（MODULE 构建参数），vscode/infra compose 零服务引用（纯底座）。

### B/C/D 三线（2026-11-18 18:0x–19:1x，三 verify 全 PASS）

- **P7 IM**（ppb-chat worktree vscode/ppb-chat-wt，分支 refactor/ppb-repository-layout-im）：merge `bd9a72ad`（双父无公共祖先，第二父线可达历史 165 commits；service-im/deploy 树与源逐字节一致，仅剔除 37MB deploy/bin/im 与 25MB e2efixture 陈旧产物）+ module 迁家 `4bc0f697`（229/229 纯 import 行重写）+ 勘误 `a5373ada`。GOWORK=off **16 ok/0 FAIL**。deploy/rtc 经查证为 IM/RTC 专属随迁（ppb-base 保留自有副本，收敛挂 P8）。登记：ppb_im.db 86KB 种子库随迁（<1MB 阈值合规，退役另议）、rtc/friendevent 留守 server-pkg 桥接（P7b）。
- **P6 Camera**（ppb-camera worktree vscode/ppb-camera-wt，分支 refactor/ppb-repository-layout）：merge `bbeee88`（第二父线 18 commits 至骨架 e8fc0ac）+ module 迁家 `1de972d`（70/70 纯 import）。GOWORK=off **9 ok/0 FAIL**。RTC 与 camera 零交集确认（grep 命中全为子串误报）。dev 占位 jwt_secret 随历史迁入（ppbchat-dev-jwt-secret，投产前部署层覆盖——原 ppb-base 既有状态非本批引入）。
- **P4a 前端公共包**（ppb-base worktree p4-frontend，分支 refactor/ppb-repository-layout-p4，5 提交至 b8eb564）：base-manage-web 库/演示双产物（dist-lib + types，files 白名单、exports 三条件、peerDeps 镜像）；npm pack 消费实证——临时 Vue3 工程装 tarball，全谱 import（工厂/插件契约/10 组件值+类型/样式子路径）+ 22 个导出类型 any 探测（含负向对照），vue-tsc --noEmit 零输出。private:true 保留（P4b 发布链待办）。
- **跨线修复**：P4a 验收发现 ppb-chat `4171c131` bizKey→menuKey 改名打红 ppb-base 主检出 base-manage-web 测试——修复 `b8eb564` 已 cherry-pick 至 ppb-base main（`2ad1e37`，未推送），主检出 npm test **163/163 恢复绿**。


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
- 已知缺口、阻塞与可继续工作：**G7** gh CLI 已装未登录（token 认证需用户 `gh auth login`，或网页建私有空仓 maibanku/ppb-{iam,gateway,file}），三新仓未设远端未推送；G4 RabbitMQ 未部署沿用；前端 typecheck 须 **node 24.x**（homebrew node 25.2.1 下 vue-tsc 出 33+47 条伪影错误，24.21.0 下零诊断——CI 应锁版本）；ppb_user*.sql／seed_menus.sql／00-create-databases.sql／deploy/docker/Dockerfile.service／tools/gen-routes 留守 ppb-base（P2/P4/P8 裁决）；原仓移除与部署引用切换未做（P8 序）。P1 独立评审已收口：**APPROVE_WITH_NITS**——垫片保真（逐字迁移/AddCallerSkip 口径/ctxKey 同一性/errors.Is 同值/文案逐字节）、模块边界、死代码退役、五服务零 diff、GOWORK=off 独立重跑全过；M1（internalauth 垫片 gofmt）已修 `8f85abe`；N1 idstr/requestid 存量 gofmt、N2 kafka 品牌串 ppbchat-bus- 参数化、N3 03 文档模块表补 gormx/messaging-kafka 两行（已补）、N4/N5 记录性修正——除 N3 外挂 P2 发布批。可继续：P2 契约/SDK。**完整性审计补强（17:45）**：三仓文件平价与源路径集合精确吻合（iam 279-2二进制+3根文件=280、gw 20-1+3=22、file 107-1+3=109）；三前端 `npm run build` 全过（vite 构建期别名解析实证）+ `npm test` **31/283/12 全过**（node 24.21.0），构建后三仓树仍干净；残留旧兄弟路径引用扫描=0（唯一命中为 MIGRATION.md 历史值记载，文档性）。三仓调整就本机可验证口径**已完成**。
- 回退依据与下一步：三新仓为独立目录，删除即回退；ppb-base 主检出/运行态零改动；P1 线独立 worktree 可整线 revert。下一步：P1 评审收口 → P2（grpc_gen/user-compat/refaccess 契约 + platform-sdk/iam、file 客户端）→ tag 发布与 replace 切换 → 远端建仓推送（G7 解除后）。

P2a 评审收口（同日）：**APPROVE_WITH_NITS**。活体验证全部在 git archive 副本进行（未碰实施 worktree）。线面零变化升级为**全 8 域 FileDescriptorSet 级证明**（基线/终态两状态 buf build 描述符剥 options 后全等，唯一差异 goPackage）；单注册/垫片完备（FullMethodName 257/257 零缺、导出符号集合全等）/模块自洽/消费方零改动/endpoint-audit 相对路径全 PASS。**I1（Important）**：CI gateway-governance 的 buf 漂移门禁仍守 server-pkg/grpc_gen 旧路径→空转，需一行改 `-- contracts server-pkg/grpc_gen`——已转 P2b 批顺带独立提交。M1/M2（报告措辞与中间提交幂等性）、N1-N3（措辞/func→var 固有代价/buf-lint-baseline 格式无法 key 匹配——范围外建议另行修）登记在案。未核对项五条明示（01 文档本体、66 测试未全量重跑、运行期反射、gen-routes CI 步、三新仓构建实测）。
