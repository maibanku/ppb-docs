# 单端口 + 统一 JSON 映射：目标架构总结（分析起点）

> 日期：2026-11-23 · 性质：三份既有分析的合成结论，供决策与分期排期
> 合成自：`single-port-analysis.md`（端口分析）、`external-api-over-rpc-design.md`（JSON 映射设计）、
> `grpc-to-http-howto.md`（引擎机制）、`adr-gateway-http-proxy.md`（现状定案）

## 一、目标形态一句话

**每个内部服务只剩一个 RPC 端口（Kitex）；全部对外暴露统一收敛到网关，用现有
servicehttp 契约 JSON（或 proto 注解生成）做 HTTP↔RPC 翻译——即「内部纯 RPC
单口 + 网关统一 JSON 映射」。**

```
现状（每服务两口）                    目标（每服务一口）
─────────────────                    ─────────────────
客户端 → 网关 → 服务HTTP面(911x)      客户端 → 网关(8080, 唯一 HTTP 入口)
                  ↓ 回环RPC                    ├─ 契约 JSON ×7（Bind/Reply/svcauth）
                  Kitex(910x)                  ├─ kitex client（etcd 发现+熔断）
                                               └──RPC──> im:9102 / file:9104 /
                                                         camera:9106 / iam:9107
```

## 二、核心结论（不可绕过的三条）

1. **单端口不是合口是搬家**：Kitex 无任意 HTTP handler 托管（detection 只收
   RPC 系协议），HTTP 面同口共存不可行（路径 C 已否决）——唯一路径是把
   HTTP 翻译从服务进程挪到网关（字节同构，路径 A）。
2. **JSON 映射层已存在且可整体搬迁**：7 份契约 JSON + servicehttp 引擎
   （Bind/Reply/信封/防伪造注入）+ svcauth 中间件族全是 ppb-base 共享件，
   网关加载即得；`Invoker` 从回环 LocalConn 换 kitex client（Phase C 出站件
   已验证同语义）。**服务侧 handler、契约、业务代码零改动。**
3. **三个硬前置挡在前面**（HTTP 面上无法 bind/reply 化的车道）：
   file 的 multipart/Range 流式 → 对象存储预签名直传；im 的 /ws → 独立接入
   进程（或网关长连接能力）；iam 的 OIDC 重定向端点 → 随认证门户独立。

## 三、分期路线（每期独立可交付）

| 期 | 内容 | 独立收益 |
|---|---|---|
| **S0 文件直传** | MinIO 预签名 URL 直传直下，服务只签凭证；下线 file_transfer 车道 | 服务带宽卸载（**无论是否单端口都值得**，≈2-3 天） |
| **S1 WS/OIDC 独立化** | WS 接入独立进程（im 收敛纯 RPC）；OIDC 端点随 iam-web/门户 | ≈2-3 天 + 1-2 天 |
| **S2 网关契约化** | 网关加载 7 份契约 + servicehttp 引擎 + svcauth 链 + kitex client；灰度按服务切换（先 camera 29 条试面） | 服务去 HTTP 口，端口 8→4；网关获契约视图（统一限流/审计） ≈3-4 天 |
| **S3（演进）注解生成** | proto `google.api.http` 注解 → 生成契约 JSON（`make gen-api`） | 手写契约归零 ≈1 天 |

## 四、不变清单（搬迁安全性的根据）

- contracts proto + gen/go（类型事实源）
- 服务 handler（`*_kitex.go`）与全部业务代码
- 鉴权语义（member/manage/subject/anonymous 四面链，原样随迁）
- 信封协议（BaseResp↔HTTP 映射）与 operator 防伪造注入
- etcd 注册/发现、Phase C 出站、冒烟四家（探针地址改网关）

## 五、风险与回退

- **鉴权跨进程搬迁的安全复审**（最高风险项）：中间件从进程内移到网关，
  签名密钥分发面扩大——需专项 review（S2 前置）
- 网关成为单点：现已是唯一入口，风险不新增；契约化后加缓存/限流反而增强
- 回退容易：按服务灰度（service→gateway 切换是一行 upstream/契约装载选择），
  服务 HTTP 面可保留一段双跑期再拆

## 六、待决策

1. 是否立项（建议：S0 立即——独立收益明确；S1-S2 待 S0 验证后批）
2. im 出站灰度开阀（im→iam/file 上 Kitex，deploy 两行）可搭车同批
