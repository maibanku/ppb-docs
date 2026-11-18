# PPB 架构改造实施进度

## 当前检查点

日期为 2026-11-18。P0 基线、P1 基础模块提取（P1a 盘点／P1b 轻量五包／P1c 四适配模块+两死包退役）与三新仓拆分（ppb-iam／ppb-gateway／ppb-file）已实施；P1 独立评审在途。公共模块尚未打 tag 发布，三新仓仅存本地分支，远端仓未创建（缺口 G7）。

| 阶段 | 状态 | 当前证据 |
|---|---|---|
| 文档与静态分析 | 文档已编写 | architecture 目录及现有入口更新 |
| P0 本地工具／运行基线 | 已执行 | [P0 证据](p0-evidence.md)：工具/五仓 SHA/六模块/15:39 运行态实测 |
| P1 框架与适配 | 完成（评审 APPROVE_WITH_NITS） | worktree p1-framework：925fd32（P1b）+ 9e9c478..ff88bbe（P1c）+ 8f85abe（M1 gofmt）；11 模块 66 ok/0 fail |
| P2 契约与 SDK | **完成——v0.1.0 本地已 tag（13 枚@59fb6d0）** | contracts×6+platform-sdk×2+go-framework×5 全评审链收口；远程读取验证与 go.sum 收尾 tidy 待 G7 推送后 |
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

### P2b platform-sdk（2026-11-18，worktree p1-framework 093928f..ce44d25）

- 提交：7f8a94b（platform-sdk/iam：svcauth 核心+authzport+authzguard+edgeauth+垫片）、a910248（IAM SDK 四态错误处理+ValidateSession 两态区分+测试）、ff08b21（platform-sdk/file：File SDK 客户端自 im rpcclient 公共化）、202a1c2（**RegisterFileMeta 四类回执校验——00 文档登记缺陷修复，复现保存**：旧实现 biz-fail→(0,nil)、zero-id→(0,nil)、mismatch→(999,nil) 静默；现 KindBiz/KindReceipt 显式返回）、cc95a13（I1 CI 漂移门禁改 `-- contracts server-pkg/grpc_gen`）、ce44d25（notes+README）。
- 证据：两 module GOWORK=off 自洽全过；工作区 **19 模块 69 ok/0 FAIL**（基线 66+3 新 SDK 测试包，零回退）。SDK 四态 8+6 用例（互斥断言）、四类回执 5 用例 -race（16 路并发幂等）。消费方零改动。
- 结构裁决：svcauth 半拆分（核心迁 SDK，HTTP 装配面/envelope 留驻 server-pkg 经 forward.go 直通——envelope 是跨前端线契约，P2a 裁决延续）；iam module 依赖 contracts/{iam,common,im,user-compat}+go-framework{根,rpcx}（盘点明文含 im 成员判定半边）。
- 遗留登记：server-im 私有 rpcclient 副本仍带原缺陷（im 切 SDK 消费时修复，p2b-notes）；envelope 归位裁决；三新仓 post-merge 需补 platform-sdk/iam replace；四态 taxonomy 两 SDK 各自同形（有意独立）。

第二波并行登记（19:3x 起）：P2b 评审（归档副本）∥ P7b rtc/friendevent 迁 ppb-chat（ppb-chat-wt，P2 杂项分仓避免双写者）∥ P2 杂项（idl proto 迁 contracts、errcode BizError 归位、lint-baseline 修，p1-framework）∥ P4b 三线（iam+file/chat/camera manage-web 插件化）∥ P8 前置（gen-routes 清单化、每服务 Dockerfile、P8-SWITCH 方案，p8-deploy worktree）。

### P7b + P2b 评审（2026-11-18 20:0x）

- **P7b**（ppb-chat-wt，ec59a45b+912dbf12）：rtc/friendevent 经 filter-repo 历史迁入 service-im/pkg/（4 条触达提交保留；迁入包源码零改动——两包不依赖 server-pkg 其它件）；service-im 消费切换 10 行 import；**17 ok/0 FAIL**（基线 16+rtc 自带测试）；守卫 0。登记：与 ppb-base server-pkg 原件双份并存至 P8 统一退役（退役前避免两仓并行改同名包）。
- **P2b 评审收口：APPROVE_WITH_NITS，零阻塞**。四态互斥结构性成立（ErrIdentityInvalid 仅 KindBiz 装载；err≠nil 时 gRPC 恒 resp==nil，击穿不可能）；RegisterFileMeta 修复经 server-file 源码核实回执前提、16 路真并发（srv.calls==16 断言+-race）；svcauth 半拆分 forward 纯别名+导出面 100% 全等（76 符号探测）；19 模块 69 ok 独立复现精确相符。Minor×2（SDK 测试钉子三条、依赖文档漏 jwt/v5）已作 rider 转 P2 杂项批顺带；Info×2 登记不处理。refType=2 mail 域为真实活契约非 YAGNI。

### P4b 第一波（2026-11-18 20:2x，三线 verify 全 PASS）

- 四个业务 manage-web 插件化导出面落地（纯增量，行为零变化——验收做到结构级：main.ts 模块图未变、.vue 零触碰、路由表零编辑）：
  - ppb-iam/iam-manage-web `5a705ef`+`64f7975`：iamManagePlugin（13 治理路由+beforeEnter is_super∨iam.*.read）+registerIamManagePlugin+13 条菜单权限清单；**287/287**（基线 283+4）。
  - ppb-file/file-manage-web `0a112f8`+`bf8da3e`：fileManagePlugin（5 路由）+5 条清单；**16/16**（12+4）。
  - ppb-chat-wt/chat-manage-web `d741c1fc`+`ec92d1d7`：chatManagePlugin（13 /chat/* 路由、12 入菜单、10 权限码，Pick<BizRouteDef> 派生投影）+installChatManagePlugin；**90/90**（87+3）；一次性真实底座注册表冒烟（getPlugin('chat') 持全路由）后已清理。
  - ppb-camera-wt/camera-manager-web（两提交）：cameraManagePlugin+清单；三件套绿。
- 契约类型全部 import 自 base-manage-web/exports（零复制）；registerPlugin 仅函数体内调用（无顶层副作用，不破坏 tree-shaking）。各仓 package.json 落 exports map（./、./exports、./plugin——后者为 platform-manage-web 现行 vite alias 深路径的切换预留，验收实证 portal 今日仍绕过包解析直连 src/plugin.ts）。
- 第二波遗留（各仓 docs/p4b-notes.md 登记）：发布链（dist-lib/files 白名单/peerDeps/npm pack 实证，对齐 P4a 形态）、vendor 门面收编、file 仓 vitest resolve 口径统一、portal 消费切换、chatMenuPermManifest 门户装配自检/种子 SQL 对账。

### P8 前置批（2026-11-18 20:5x，worktree p8-deploy，评审 APPROVE_WITH_NITS 后 L1/L2 已修）

- 提交：2dd5d77（**gen-routes 清单输入化**——deploy/route-manifest.yaml 六服务各一条；model/manifest/scan 三分；硬校验：缺清单（go.work 交叉核对）、未知上游三态、方法路径归属/前缀冲突→生成失败；-scan 旧模式保留；CI 扩 test+清单漂移+对拍）、46ecf68（per-service Dockerfile×5，buildx --check 全过；mail 无件=外部独立部署本仓无源码）、249e83d（**deploy/P8-SWITCH.md**——现状基线/前置/四步切换/旧制品保留/回退/移除三门/rtc 双副本收敛/mail 口径/检查表）、402987a（评审 L1/L2 修正）。
- 评审证据：**四方逐字节等价独立复现**（新清单模式/-scan/base 旧工具/已提交 gateway-routes.yaml，147 路由+1 前缀 cmp 全 0）；16/16 测试复跑；HEALTHCHECK 五端点与实码逐一核对；compose 六项/路由三副本/rtc 双副本事实核对。L1（6fc8c39 悬空→真实 4cbee90，三处+compose）、L2（replace 形态改写提示，五件）已修。N3/N4（前缀遮蔽/specials key 拼错不检测）入 P8 主批可选加固清单。
- 门前裁决登记：gateway-routes 第三副本（ppb-gateway 仓）收敛两案——倾向镜像兜底+CI 对拍（P8-SWITCH §3 Step 4），主批定案；「清单版本+校验摘要」记录未实现（可选后续）。

### P2 杂项评审收口 + 发布准备启动（2026-11-18 21:0x）

- **P2 杂项评审：APPROVE_WITH_NITS，核心声明全部真跑复现**——8 proto R100 rename 与 --follow 穿透；buf 双轮 diff 空（15 pb.go 逐字节）；errcode 三向 Code 同型（sp↔cec↔gf）编译+运行探针、AST 导出集合全等；lint 基线 1402 全量逐字节对齐+负例注入 exit 1 实证；功能性 idl/ 残留=0（51 处全为注释/rawDesc/废弃脚本）。Minor-1（Unauthenticated 钉子缺防误桶断言）转发布准备批 rider；Minor-2 报告措辞勘正；Info×2 不处理。
- **发布准备批在途**：13 公共模块（go-framework×5 + contracts×6 + platform-sdk×2）撤家族 replace、兄弟引用 v0.0.0-占位→v0.1.0——tag 前终态；server-pkg/五服务 replace 不动（不发布）。tag 由协调方在终态提交统一打，远程依赖读取验证（空模块缓存）待 G7。

### 第二波总收口（2026-11-18 21:2x）——13 模块 v0.1.0 本地 tag 完成

- 发布链终态：3030c02（M1 钉子保险）→ 59fb6d0（发布准备：20 处家族 require→v0.1.0、14 条家族 replace 撤除、工作区 19 模块 69 ok 改动前后等价、五服务/server-pkg/go.work/go.sum 零改动）→ **13 枚 annotated tag 统一打于 59fb6d0**（go-framework、rpcx、gormx、mq/rabbitmq、messaging/kafka、contracts/{common,iam,file,im,camera,user-compat}、platform-sdk/{iam,file}，均 /v0.1.0）。
- 实施偏差登记：go.work 模式下 tidy 不感知工作区仍向 proxy 解析兄弟版本（只读失败）——一致性由「仅版本串/删 replace+sum 零改动+全量 build/test 等价」背书；go work sync 会越界改写非发布模块 go.mod，禁用。
- **待 G7 的收尾**（tag 推送后一次性执行）：① push 13 tag；② 13 模块 GOWORK=off go mod tidy 各一遍（补兄弟 v0.1.0 go.sum 哈希——replace 时期不需要，现已可独立解析但本地无远端源）；③ 临时空模块缓存 GOWORK=off 真远程读取验证（03 文档要求，未执行不得记"已发布验证"）；④ GOPRIVATE=github.com/maibanku/* 配置口径通报 CI。
- 环境注记：本机 /etc/paths.d/go 指向不存在的 /usr/local/go，go 经 ~/sdk/go1.26.0/bin 或 GOTOOLCHAIN 缓存 go1.26.10 解析（PATH 缺口 G5 延续）。

## 全程波次总账（截至 21:2x）

| 批 | 状态 | 评审 |
|---|---|---|
| P0 基线 / P1b / P1c | 完成 | P1 评审 APPROVE_WITH_NITS（M1 修） |
| 三仓拆分 iam/gateway/file | 完成（verify PASS×3+修复轮+终验） | 完整性审计补强 |
| P2a 契约 / P2b SDK / P2 杂项 | 完成 | 三评审全 APPROVE_WITH_NITS（I1/M4/M6/L1/L2 已修） |
| P7 IM / P7b rtc·friendevent / P6 Camera / P4a | 完成 | verify PASS×4 |
| P4b 第一波（四 manage-web 插件化） | 完成 | verify PASS×3 |
| P8 前置（gen-routes 清单化/Dockerfile/SWITCH） | 完成 | APPROVE_WITH_NITS（L1/L2 已修） |
| v0.1.0 发布准备 + 13 tag | 完成（本地） | 依赖 G7 远程验证 |

未完清单：G7 推送（用户 gh auth/建仓）→ tag 推送+tidy+远程验证 → 消费方切换波（五服务+三新仓 import 切 maibanku 模块、撤 server-pkg replace）→ P1/P2 线合 ppb-base main（征授权）→ 三新仓补 contracts/platform-sdk replace 或直切远程 → P8 主批（镜像切换/旧家移除/ rtc 收敛/验收矩阵）→ P4b 第二波（发布链/portal 消费）。G4 RabbitMQ 部署决策仍待用户。

### P4b 第二波（2026-11-18 22:3x，四仓发布链形态完成）

- 提交：ppb-iam 3a07044+a8ec90f、ppb-file 6d69ea9+5243320、ppb-chat-wt 371958c0+3fe917c9、ppb-camera-wt 2e24436+7383aac。
- 每仓同构：vite.lib.config.ts（库模式，vue/EP/icons/base 全外置 peer）+ tsconfig.lib.json（d.ts 发射）+ rewrite-dts-alias.mjs（'@/' 相对化+base specifier 重写，残留即失败）+ lib 专用类型门面 + package.json（exports 三条件双入口、files 白名单、deps→peerDeps）。
- 验证：四仓 typecheck/test/build/build:lib 全绿（**287/16/90/21 用例不回退**）；npm pack 消费实证——插件+base 双 tarball 安装、"."与"./plugin"双入口、Equal 非 any 断言+负向对照（报错带真实类型名）、style.css/SFC，vue-tsc skipLibCheck:false 零输出；tarball 零 src/dist/lockfile。
- **base 依赖打包裁决**：file: 相对路径随 tarball manifest 必炸消费 install → peerDeps "*"（同时满足本仓 v0.1.0 与消费侧 base v0.2.0）+ devDep 本地桥接（npm 不解析已装依赖 devDeps，惰性无害，四仓实测）。
- 第三波遗留（各仓 docs）：JS 运行时 'base-manage-web/exports' specifier 经 base 包 exports 映射解析到 exports.ts（TS 源，vite 宿主可编译）——接 registry 后切真实 JS 产物，两代门面一并退役；lib 门面双同步漂移窗口随之根治。
- 构建残留两枚（22:26 误落 ppb-base 主检出 src 旁 .d.ts）已由协调方核实未跟踪后清除。

### 消费方切换波（2026-11-18 23:0x）——本地迁移面穷尽

- 提交（59fb6d0 之上，每服务一提交）：724f0ea gateway、0e351ae iam（59 文件）、735852c file（36 文件）、70d71a2 camera（24 文件）、4383dd1 im（115 文件）。
- 映射落地：logx/requestid/idstr/health/snowflake→go-framework；grpcrid→rpcx、recovery/internalauth→rpcx/interceptor、database→gormx、eventmq→mq/rabbitmq、event→messaging/kafka；grpc_gen 六域→contracts（refaccess 归 file、user 归 user-compat）；authzport/authzguard/edgeauth→platform-sdk/iam；errcode 双段拆分（BizError→contracts/common、机制段→go-framework，混合文件 gferrcode 并存）；svcauth 核心件切 SDK、装配面 svcauthmw 并驻。
- 验证（含协调方抽验）：19 模块 **69 ok/0 FAIL 不回退**；零漏切（五服务 server-pkg 残留恰=留守集合 envelope/servicehttp/svcauth 装配面/obs/rtc/friendevent）；im 16 ok 与 iam 残留四件抽验吻合；树净。
- 技术登记：离线 tidy 需临时挂本地 replace 后撤（go1.26 tidy 不认 use 解析）；server-iam 外科式 8 条直增 require（otel 链离线不可拉）；golang/protobuf v1.5.4 锚定于 server-im（server-pkg servicehttp APIv1 未列根因，根治待其本体收口）；go.work.sum 净收敛（gateway -21/im +7）。
- **至此，迁移改造在无远端/无运行时授权条件下可执行的工作全部完成**。剩余全过闸门：G7 推送（六仓分支+13 tag+远程读取验证+13 模块 tidy 收尾）→ P1/P2 线合 ppb-base main（授权）→ 三新仓切 maibanku 模块（post-merge）→ P8 主批（镜像切换/旧家移除/rtc 收敛/验收矩阵）→ P4b 第三波（registry 接入+运行时 specifier 收口）。G4 RabbitMQ 决策待用户。

### G7 部分解除（2026-11-19）

- 用户建仓并显式授权推送：**ppb-iam、ppb-file 已推 GitHub（maibanku，HTTPS origin，分支改 main，upstream 已设）**——含各自全部迁移历史与 P4b1/P4b2 提交。
- 仍待：① ppb-gateway 远端仓不存在（ls-remote Repository not found）；② ppb-base refactor 分支 + 13 枚 v0.1.0 tag 未推送（tag 推送=正式发布，待用户确认）；③ 由此远程依赖读取验证与三新仓消费切换仍挂起。

### v0.1.0 正式发布 + 终波启动（2026-11-19）

- **三新仓上线**：用户建仓并授权——ppb-iam、ppb-file、ppb-gateway 均已推 GitHub（HTTPS origin，分支改 main，upstream 设定）。
- **ppb-base**：refactor/ppb-repository-layout 分支已推（cb3047f→6170350）。
- **14 枚 tag 已发布**：13 公共模块 v0.1.0 + **server-pkg/v0.1.0 过渡发布**（占位→v0.1.0、撤 12 条家族 replace；envelope/servicehttp/obs/svcauth 装配面暂驻其内作远程桥，最终归位裁决在册）。
- **远程解析实证**：13 模块 GOWORK=off tidy/build/test 13/13、19 ok/0 fail（GOPRIVATE=github.com/maibanku/*,github.com/ppbchat/*；go 下载日志可见 maibanku 拉取）。
- **终波在途**：五业务仓（ppb-iam/ppb-gateway/ppb-file/ppb-chat-wt/ppb-camera-wt）消费切换全远程化——撤本地 replace、require v0.1.0、GOWORK=off 独立构建验收（gateway 线另做 GOMODCACHE 全冷下载面实证）。此波过后「新电脑只检出业务仓即可构建」验收成立。
