---
name: cross-session-dispatch-mode
description: 本机无 Agent 工具时的多会话并行派发模式（SendMessage 任务书→空闲会话→回执→我集成提交）
metadata:
  type: feedback
---

用户明确要求"多 agent 并行"时，本 VSCode 扩展环境无 Agent/Workflow 工具（已多次验证），可行等价模式（2026-10-28 实战验证双会话并发成功）：

**Why**: 用户要并行吞吐；ListAgents 可见的空闲 Claude 会话就是可用执行体。

**How to apply**:
1. ListAgents 选 idle 会话；SendMessage 发任务书：自包含背景+精确文件范围+验收命令（PATH 含 go sdk）+**禁止 commit/推送/重启**+回执要求（改动清单+测试结果）。
2. 我继续做自己的域；回执到达后**复验三连**（build/vet/test 自己再跑）+ 抽查关键点 → 我统一集成提交（attribution 注明实施会话）。
3. 派发书要圈定禁碰区（如在途他人文件）；受派会话可能顺带发现你的责任项（本次 permguard 夹具漏改即由 vscode-91 揪出）——重视回执里的"范围外发现"。
4. 安全检查会拒绝无法静态解析的长脚本（含死函数/乱引号必被拒）——脚本必须干净直白。
