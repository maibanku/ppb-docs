# 改造方案：服务器之间 100% RPC——IAM 业务桥退役（换凭证删桥）

> 日期：2026-11-23 · 目标：消灭唯一的内部服务间 HTTP 互调（IAM 业务桥），
> 东西向流量 100% 走 RPC（gRPC 线缆：kitex/grpc-go）
> 前置核实：bridge 路径映射（`/iam/api/v1/business/**`→`/api/v1/manage/**`）、
> svcauth `typ=manage` claims 形态、网关 `/api/v1/manage/**` 车道全量在役
>
> **执行状态（2026-11-23）**：方案 B 六步之第 1 步（服务半）已落地——
> `ppb-iam@feat/bridge-retire-manage-token 0ab2a30`：换发端点 + 测试 +
> 配置（deploy iam.yaml `jwt.manage_jwt_secret`）。token 经承接服务同款
> svcauth.Validator 验签通过（线缆兼容实证）。剩余：第 2 步 iam-web 前端
> 拦截器（Bearer）→ 双跑观察 → 第 5 步删桥。

## 一、两案对比

| 方案 | 做法 | 判定 |
|---|---|---|
| A. 桥 RPC 化 | iam 桥加载 im/file/camera 三家 manage 契约，Bind→kitex 调用→Reply | ✗ iam 进程宿主别家契约（违背「契约随服务走」落位原则）；S2 网关契约化时全部返工——桥换个地方再写一遍 |
| **B. 换凭证删桥（推荐）** | Cookie 会话在 IAM 换短期 manage JWT → iam-web 走网关标准 manage 车道 → 服务 ManageAuth 直验 → **删桥** | ✓ 服务器之间**新增调用为零**；复用全部现有件（ManageAuth/guard/网关车道）；删除代码而非新增 |

## 二、方案 B 六步

1. **IAM 签发端点** `POST /iam/api/v1/business/manage-token`
   Cookie 会话校验（active + 平台管理员/应用权限）→ 签 `typ=manage` 短时 JWT
   （subject=actor，HS256 共享 manage secret——各服务 ManageAuth 现行验签口径，
   TTL ≈20min，401 触发重取）
2. **iam-web 前端拦截器**：manage 调用前确保 token，`Authorization: Bearer`
   替代 Cookie；路径改经网关（`/api/v1/manage/**`）
3. **网关**：零改动（manage 车道 136 条中已全量存在）
4. **服务侧**：零改动（ManageAuth 已验 manage JWT；guard 回源 perms 已是
   kitex RPC）
5. **删桥**：`internal/bridge` + boot_wire 挂载 + 测试；治理拒绝段
   （audit/iam、email-log）规则迁至 token 签发侧或 iam 自有面
6. **回归**：iam 双路 smoke + 管理台端到端（Cookie 登录→换 token→四服务
   manage 面）+ 四服务全量测试 + 文档收口（internal-rpc-howto 例外条目撤销）

## 三、兼容与回退

- 双跑期：桥保留，前端 token 获取失败回退桥路径；观察期后删除
- 回退 = 前端切回 Cookie 直调（配置级）

## 四、估时

后端端点+测试 0.5-1d ｜ 前端拦截器 0.5d ｜ 删桥+回归 0.5d ≈ **2 天**

## 五、终态全景

```
服务器之间（东西向）：100% RPC
  ├─ 主干出站：kitex（灰度开）/grpc-go（im 回退腿、file→mail）
  ├─ guard 回源：kitex（AdminAuthz/RbacVersion）
  └─ 服务间 HTTP：0（桥已删）
边界外呼（非服务互调，不变）：LiveKit Twirp / GitHub OAuth
对外：网关唯一 HTTP 入口（manage 车道验 manage JWT）
```
