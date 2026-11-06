# Claude Code 执行任务

本文件是实施交接说明，不表示 Claude Code 已启动，也不表示代码已完成。

## 给 Lead 的任务指令

```text
在 /Users/pipi-ban/Desktop/code/vscode/ppb-base 实施网关接口治理改造。
先读取仓库实际适用指令，再按顺序阅读：
/Users/pipi-ban/Desktop/code/vscode/ppb-docs/gateway/README.md
以及它链接的技术设计、实施步骤和验收标准。

目标：保留现有公开行为、Gin、gRPC、响应信封和权限边界，修复 Registry
冲突机制，建立完整 API 目录，以 todo 域完成 HTTP 契约生成试点。
按 G0→G1→G2→G3→G4 推进；G3 不通过不得扩大到其他域。
完成后按 G5 逐域迁移，特殊编排与特殊协议保持显式适配。

先核实 HEAD、dirty files、实际代码，不把文档中的目标路径当作已存在。
不要覆盖其他 Claude/Codex 任务，不清理或重置他人改动。
契约、安全策略和目录必须可校验；禁止自动公开全部 RPC。
禁止手改生成产物；禁止改返回结构迁就生成器；禁止移除已有鉴权或 fail-closed。
普通用户身份字段必须由可信上下文注入，不能直接相信 body/query/header。

每一阶段先补必要的失败场景测试，再实施并验证；在真实本地环境验证试点业务。
每阶段小步提交，已有推送授权范围内推送；不要 git add -A。
验收不足就继续定位并记录，不得写“全部完成”。
遇到外部凭证缺失、服务不可用或无法保留契约时，明确记录阻塞与证据；
继续可独立完成的工作，不能伪造实测结果或隐藏失败。
```

## 团队分工与依赖

可以使用 Claude Code 自身支持的 subagent/agent team；先以本机 `claude --help` 确认能力，不虚构参数。多人实施用独立 worktree/分支，Lead 集成。

| 角色 | 工作 | 依赖与写入边界 |
|---|---|---|
| Lead | 基线、架构、接口模型冻结、集成、提交、验收 | 独占 main.go、gateway_routes.go 及最终契约决策 |
| Registry Worker | G1、G2 目录核心与测试 | 独占 method_registry.go 和 apicatalog 核心；先与 Lead 确认模型 |
| Contract Worker | todo HTTP 注解、工具链、生成适配器 | G2 模型冻结后开始；不得同时改 Registry 核心 |
| QA/Docs Worker | 基线 fixture、兼容矩阵、CI 建议、验收文档 | 可先只读审查；CI 与共享文件改动经 Lead 集成 |

G0 可以并行调查；G1/G2 的模型设计必须顺序收敛。不要多个 worker 同时修改 policy.go 或同一装配文件。独立 worktree 的依赖提交由 Lead 明确合入，避免 worker 基于不同模型实现。

Lead 每轮检查 worker 的实际 diff 和测试输出；不能把 worker 的“完成”摘要直接当验收结果。安全策略、身份注入和写操作由未编写该代码的审查者复核。

## 进度与恢复文件

在 `ppb-docs/gateway/ac/执行记录.md` 记录：

- 本轮时间、两个仓库 HEAD、执行阶段与负责人。
- 本轮修改文件、提交 SHA、推送状态。
- 实际测试命令、退出码、证据位置，区分自动测试和真实环境测试。
- 每条验收项 PASS/FAIL/BLOCKED/NOT_RUN；阻塞原因与下一步。
- worker 分支、会话恢复 ID（若工具提供）及剩余任务。

上下文不足前先更新记录。恢复时先读该文件、检查 git log/diff，再继续；不要从摘要推断任务已完成。

## 启动方式

在终端进入代码仓库后启动本机 Claude Code：

```sh
cd /Users/pipi-ban/Desktop/code/vscode/ppb-base
claude
```

输入：

```text
读取 /Users/pipi-ban/Desktop/code/vscode/ppb-docs/gateway/implementation/Claude-Code-执行任务.md，
按其中任务和依赖执行，先提交 G0 基线与 G1 注册校验，逐阶段验证并更新执行记录。
```

本文件不要求关闭权限检查，不要求终止其他会话，也不启动定时任务。实际授权范围以当前用户指令和执行环境为准。

## 查看进度

```sh
git -C /Users/pipi-ban/Desktop/code/vscode/ppb-base log -8 --oneline
git -C /Users/pipi-ban/Desktop/code/vscode/ppb-base status --short
cat /Users/pipi-ban/Desktop/code/vscode/ppb-docs/gateway/ac/执行记录.md
```

执行记录将在任务实际开始后创建；未创建不能解释为任务已经完成。进程存在只能说明工具在运行，进度以提交、diff 和验收证据判断。
