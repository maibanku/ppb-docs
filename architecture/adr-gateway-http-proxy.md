# ADR：网关维持 HTTP 反代（Kitex 迁移战役终局决策）

> 日期：2026-11-23 · 状态：**已定案（维持现状）** · 触发评审：复盘遗留项 #10
> 关联：`kitex-migration-plan.md`（总体策略修正）、`kitex-issues-retrospective.md`（#10）

## 背景

Kitex 迁移完成后的请求拓扑：

```
客户端 → 网关(:8080, httputil.ReverseProxy 纯透传, 136 路由)
       → 各服务 HTTP 面(:911x, servicehttp 契约层)
       → 回环 gRPC(grpc-go LocalConn, 标准线缆)
       → Kitex 服务端(910x, detection 协议探测)
```

路由分布：im 88 / camera 29 / file 12 / iam 7。
HTTP 面承载：JSON bind/reply 信封、分面鉴权（subject 匿名白名单/ManageAuth/断言承接
分派）、multipart 上传、流式下载、WS 升级、OIDC 重定向——这些是**平台外部契约层**，
不是可拆除的代理细节。

## 选项

| 选项 | 内容 | 代价 |
|---|---|---|
| A. 维持 HTTP 反代（现状） | 网关纯透传，契约层在各服务 HTTP 面 | 每请求多两跳（反代 + 回环 RPC） |
| B. 网关 Kitex 客户端直达 RPC | 136 路由改 RPC 调用 + 网关侧重建 HTTP 契约面 | multipart/流式/WS/OIDC 的 HTTP 语义无法整体 RPC 化——这些端点仍需 HTTP 面，实际退化为 C 且双契约维护 |
| C. 混合（纯 JSON 透传子集走 RPC） | 路由画像后仅无 HTTP 特殊语义的子集 RPC 化 | 两套转发路径长期共存；鉴权中间件双份；收益仅限子集 |

## 实测（2026-11-23，本机，camera templates 端点）

| 路径 | p50 |
|---|---|
| 直连服务 HTTP 面（含回环 RPC + DB） | 1.58 ms |
| 经网关（多一跳反代） | 1.93 ms（**网关跳 +0.35 ms**） |
| /ping 基线（纯 handler + DB ping，无回环） | 0.73 ms |
| **推算：契约面 + 回环 RPC 整跳** | **≈ 0.85 ms** |

## 决策

**维持 A（HTTP 反代）为长期架构。** 依据：额外跳数的实测成本 < 1 ms p50，而 B/C
要求重写全平台外部契约面（136 路由 × bind/reply/鉴权/multipart/流式/WS/OIDC），
风险与维护成本数量级不对称。HTTP 面定位为**平台契约层**（不是代理遗留物），
其存在价值 = 外部 HTTP 语义的唯一权威实现。

## 重开评审的量化触发条件（满足其一）

1. 端到端 P99 延迟预算文件中，本跳（反代 + 契约面 + 回环）占比 > 30% 且业务侧
   已立项优化；
2. 跨机房/多 region 部署使网络跳数成本进入显著项（本跳不再是 localhost）；
3. 非 HTTP 客户端规模化接入（内网 RPC 消费方成为一等公民）。

若触发，先做路由画像（区分纯 JSON 透传与 HTTP 特殊语义端点），按 C 路径评估，
不整仓 B。
