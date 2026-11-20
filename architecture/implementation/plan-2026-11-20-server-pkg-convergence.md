# server-pkg 物理收敛（方案 C）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** server-pkg 活包物理归位（envelope/obs→go-framework、servicehttp→platform-sdk/servicehttp 新模块、svcauth 桥退役直连），六业务仓 53 处 import 分批切换，server-pkg 收敛为 v0.2.0 纯转发壳；终态引用面 3 家（contracts / go-framework / platform-sdk），六仓零 server-pkg require。

**Architecture:** 类型同一性由 type-alias 直通保证——迁移期新旧路径混用编译安全；每仓一波全量切（envelope+servicehttp+svcauth+obs 同批），波内 GOWORK=off 单仓验证；gateway 最小仓试水跑通全流程后再放大仓。

**Tech Stack:** Go 多模块仓（ppb-base go.work）+ maibanku 私有模块（GOPRIVATE）+ 六业务仓（各自 go.mod）。

**Spec:** 本计划即设计定案（对话 2026-11-20 方案 C）；账本 `ppb-docs/architecture/implementation/PROGRESS.md` 追记。

## Global Constraints

- **类型同一性**：转发一律 `type X = target.X` + `var Fn = target.Fn`（零调用帧）；禁止 struct 包装（会产生第二类型致混用期编译错）。
- **单仓独立构建不回退**：每波完成后目标仓 `GOPRIVATE=github.com/maibanku/* GOWORK=off go build ./... && go test ./...` 必须绿；空缓存远程解析抽查（`go clean -modcache` 不做——用 `GOFLAGS=-mod=readonly` + 删 vendor 缓存单包 `go list -m` 验证）。
- **tag 纪律**：模块路径与真实归属一致；新 tag 才可被 require（ppbchat 404 教训）。
- **不动 contracts**（gRPC 生成代码边界）；**不动 go-framework 子模块**（gormx/kafka/rabbitmq/rpcx）。
- 各仓工作分支 `feat/server-pkg-direct`（ppb-base 为 `feat/server-pkg-convergence`），波内验证绿即本地合各自 main；**不推送**（推送由用户另行指示）。
- base 内部消费方同波切换：platform-sdk/iam/svcauth（envelope import）、tools/endpoint-audit、deploy/scripts/verify-p2-manage.sh（qatokens 路径）。
- E2E 终验：chat 波后 start-all 5/5 + verify 14/14。

## Review Focus（最易翻车五处→已钉任务）

1. **类型双身**（struct 包装垫片=编译炸弹）→ T1 壳必须 alias 直通，T1 测试含混用编译验证。
2. **wire 生成文件成对改**（`service_http_wire.go` 与 `wire_gen.go` 的 import 必须同批切）→ 各波步骤点名。
3. **go.sum 雪球**（新 require 引入全新依赖哈希）→ 每波 `go mod tidy` 后必须 GOWORK=off 构建实跑。
4. **间接依赖残留**（server-pkg v0.2.0 壳不应再带 glebarez/mysql 驱动）→ T1 检查壳 go.mod 最小化。
5. **脚本/工具路径断裂**（verify 脚本与 endpoint-audit 引 qatokens）→ T1 同批改并在 T6 E2E 实证。

---

### Task 1: base 收敛波（ppb-base）

**Files:**
- Move: `server-pkg/envelope` → `go-framework/envelope`；`server-pkg/obs` → `go-framework/obs`
- Move: `server-pkg/servicehttp` → `platform-sdk/servicehttp`（新模块，模块根即包）
- Delete: `server-pkg/svcauth`（桥退役）、`server-pkg/probe`（核实无 .go 后删）、`server-pkg/cmd`（qatokens 迁 `platform-sdk/iam/cmd/qatokens`，若其依赖仅 iam 域）
- Rewrite: `server-pkg/*`（v0.2.0 转发壳：envelope/obs/servicehttp/svcauth 四转发 + go.mod 最小化 + README 重写）
- Modify: `go.work`、`platform-sdk/iam/svcauth/*.go`（envelope import 切 go-framework）、`tools/endpoint-audit/**`（envelope+qatokens 路径）、`deploy/scripts/verify-p2-manage.sh`（qatokens 路径）

**Interfaces:**
- Produces: 新 import 路径 `maibanku/ppb-base/go-framework/{envelope,obs}`、`maibanku/ppb-base/platform-sdk/servicehttp`、直连 `maibanku/ppb-base/platform-sdk/iam/svcauth`；tag `go-framework/v0.1.1`、`platform-sdk/servicehttp/v0.1.0`、`platform-sdk/iam/v0.1.1`（qatokens 入）、`server-pkg/v0.2.0`（壳）。
- 兼容：`server-pkg/v0.1.1` 消费方在切波前不受影响；v0.2.0 壳内 alias 保证新旧混用同型。

- [x] Step 1: 移包+壳改造+内部消费方切换（含测试文件同迁；platform-sdk/servicehttp 新 go.mod：require contracts×4 + go-framework + go-framework/rpcx + platform-sdk/iam）
- [x] Step 2: 混用编译验证：临时文件同时 import 新旧两路径的 envelope 类型互相赋值、servicehttp 与壳 svcauth 中间件组合——`GOWORK=off go build` 过
- [x] Step 3: 壳 go.mod 最小化核查（无 sqlite/mysql 驱动残留）+ README 重写（如实描述 v0.2.0=转发壳+EOL 计划）
- [x] Step 4: go.work 收录新模块；base 全量 `GOWORK=off` 逐模块 build+test 绿（31 包基线）
- [x] Step 5: 打 4 个 tag + 本地合并 main，提交信息 `refactor(server-pkg)!: 活包归位——envelope/obs 入 go-framework、servicehttp 入 platform-sdk、svcauth 桥退役（v0.2.0 壳）`

### Task 2–5: 业务仓切换波（gateway→camera→file→iam，同模板）

**Per-wave Files（实测 import 处数）：**
- T2 gateway：envelope 1 处
- T3 camera：envelope 1 + servicehttp 5 + svcauth 1 + obs 1 = 8 处
- T4 file：envelope 3 + servicehttp 3 + svcauth 2 + obs 1 = 9 处
- T5 iam：envelope 2 + servicehttp 4 + svcauth 2 + obs 1 = 9 处（wire 文件在 cmd/server）

**每波步骤（模板）：**
- [x] Step 1: 全仓 sed 切 import（envelope→go-framework/envelope、obs→go-framework/obs、servicehttp→platform-sdk/servicehttp、svcauth→platform-sdk/iam/svcauth）；**wire 注入对（`*_wire.go`+`wire_gen.go`）同批切**
- [x] Step 2: go.mod：删 server-pkg require；加/升 go-framework v0.1.1、platform-sdk/servicehttp v0.1.0（svcauth 直连者确认 platform-sdk/iam 已在）；`go mod tidy`
- [x] Step 3: `GOPRIVATE=github.com/maibanku/* GOWORK=off go build ./... && go test ./...` 绿；`grep -r "server-pkg" --include="*.go"` 零命中
- [x] Step 4: 本地合 main，提交 `refactor(deps): 直连 maibanku 模块，撤 server-pkg 引用`

### Task 6: chat 收尾波 + 全栈 E2E

**Files:** ppb-chat 25 处（envelope 17 + servicehttp 4 + svcauth 3 + obs 1）+ 桌面/后端如有引用一并查（chat 仓含 chat-desktop 等，`grep -r server-pkg` 全量）
- [x] Step 1–4: 同模板切 import + tidy + GOWORK=off build/test 绿
- [ ] Step 5: start-all 5/5 起栈 + `deploy/scripts/verify-p2-manage.sh` 14/14（qatokens 新路径实证）（E2E 延后：在途框架落地后补跑——控制器认领）
- [x] Step 6: 本地合 main

### Task 7: 收口波

- [x] Step 1: 六仓 `grep server-pkg` go.mod/go.sum 零残留核查清单
- [x] Step 2: PROGRESS.md 账本追记 + 本计划勾稽 + 记忆更新；声明「server-pkg v0.2.0 壳保留一个发布周期，EOL 删除为下一批」
- [x] Step 3: 汇总报告（每波验证证据、tag 清单、终态引用面 3 家数据复测）

## Self-Review 记录

- 覆盖：方案 C 全要素（归位/退役/壳/EOL 声明）+ A 的 README 重写并入 T1；六仓波次齐；E2E 齐。
- 类型一致：新路径命名在各任务间统一（无第二种拼写）；tag 版本号与现有序列吻合。
- 比例：计划≈执行波次的骨架，无转录体；T2–5 同模板压缩。
- [ ] Step 5 未勾说明：E2E 延后——在途框架落地后补跑（控制器认领，见 PROGRESS 2026-11-20 留后续）
