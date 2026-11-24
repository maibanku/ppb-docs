# 自研组件框架替代评估

> 日期：2026-11-24 · 方法：盘点全部自研件 → 逐个对标开源框架 → 按价值/风险/耦合三轴判定
> 注：RPC 层已完成框架化（Kitex 迁移）；logx 底座已是 zap（薄封装不计）

## 一、总览矩阵

| 自研组件 | 规模 | 对标框架 | 判定 | 价值 |
|---|---|---|---|---|
| **obs 指标系统** | Registry/Handler 全自研 | **prometheus client_golang** | 🟢 **推荐替代** | 高：接入 /metrics 文本协议标准，Grafana/告警生态直连；自研 Registry 无生态 |
| **dbmigrate 四份迁移** | 723 行（im260/iam196/camera163/file104） | **golang-migrate / goose / atlas** | 🟢 **推荐替代** | 中：SQL 文件化+版本 CLI+inspect/diff 工具；四服务各自维护漂移面 |
| **契约网关（阶段4）** | 规划中（2-3 批次） | **APISIX**（etcd 原生+grpc-transcode+插件生态）/ Envoy transcoder | ✅ **定案走框架（APISIX，2026-11-24）** | 中高：省自研网关长期迭代；但 svcauth 鉴权需 ext_authz 外挂（Go 共享件搬家而非消失） |
| eventmq + eventoutbox | 524 + 678 行 | Watermill（router/middleware/重试/outbox 插件） | 🟡 弱候选 | 中低：补拉兜底/对账是业务语义，框架只省管道件 |
| 契约生成器 generate-service-http.py | 1 脚本 | protoc-gen 插件（grpc-gateway 风格注解生成） | 🟡 已在演进路线 | 中：消手写 JSON（external-api §7.5） |
| servicehttp 契约引擎 | ~1800 行 | grpc-gateway / Kratos / go-zero | 🔴 **保留** | 平台契约语义（信封/多面鉴权/operator 防伪造注入）定制成本 > 自研维护，已两轮评估 |
| rtws 实时层（WS hub+路由表） | 1463 行 | Centrifugo | 🔴 保留 | 与 im 业务深耦合（会话路由/在线表/推送协议）；独立化是部署问题不是框架问题 |
| gateway 透传（现状） | 664 行 | Envoy/Traefik/Nginx | 🔴 保留 | 181 行透传零负担；只有走阶段4 才谈替代 |
| boot/logx/requestid/envelope/errcode/idstr | 薄件 | — | 🔴 保留 | 稳定薄封装，替代是折腾 |
| svcauth/authzguard/authzport | 业务安全语义 | OPA/casbin/cerbos | 🔴 保留 | 断言线缆/RBAC 回源是 IAM 域协议，OPA 只能替换评估引擎替换不了信任链 |
| kitexmw/kitexstarter/rpcx 拦截器 | 适配层 | —（kitex 生态本身） | 🔴 保留 | 框架适配件 |
| storage objectstore | minio SDK 封装 | — | 🔴 保留 | 薄 |

## 二、推荐项详情

### 1. obs → prometheus client_golang（1-2 批次）

现状：自研 Registry + 自定义 Handler（`obs.Default().Handler()` 挂 /metrics）。
替代：prometheus client 的 Registry + 指标类型（Counter/Histogram），暴露
标准文本协议。迁移面：各服务 metrics 调用点改类型+注册；Grafana 直连收益
立现。风险低（观测面，灰度双写可过渡）。

### 2. dbmigrate → golang-migrate（每服务 0.5 批次，共 ~2 批次）

现状：四服务 Go 代码内迁移（幂等 AutoMigrate 风格），无独立版本工具。
替代：SQL 文件化（up/down）+ migrate CLI + 嵌入库模式；获得 inspect/diff/
回滚工具。风险：现有「启动即迁移」语义保留（golang-migrate 有库模式）；
需一次性导出当前 schema 为基线版本。

### 3. 阶段 4 契约网关 → APISIX（✅ 2026-11-24 定案：使用框架）

**决策**：阶段 4 网关**使用框架（APISIX），不自研契约网关**。落地时的三条
设计输入（阶段 4 开工批展开）：①契约声明仍以 `api/*-http.json` 为单一准源，
由生成器转译为 APISIX 路由 + grpc-transcode 配置（不再在网关进程内跑
servicehttp 引擎）；②鉴权走 ext_authz 外挂的薄 Go 服务（svcauth/
authzguard 共享件搬家，断言签发与回源逻辑不变）；③信封映射（BaseResp →
HTTP 状态 + `{data,code,success,message}`）与 operator/session 防伪造注入
需以插件或外挂前置/后置阶段承接——此项是 APISIX 路线的头号设计题。已并入
main 的网关翻译模式（D3–D6，进程内 servicehttp 承接）定位为**过渡形态**：
阶段 4 以 APISIX 替换其承接面，契约数据面（`contracts-*/api`）原样复用。

以下为定案时的评估原文：

若做单端口阶段 4：自研契约网关（加载 JSON+引擎+kitex client）vs APISIX
（etcd 配置原生契合现有注册中心、grpc-transcode 插件做 HTTP→gRPC、插件
生态做限流/熔断、dashboard）。鉴权：APISIX ext_authz 外挂指向一个薄 Go
服务（svcauth 共享件搬家）。**净账**：省自研网关的长期迭代，付一个鉴权
外挂进程——若团队接受外挂形态则 APISIX 优于自研。

## 三、结论

- **立即可做**：obs→prometheus、dbmigrate→golang-migrate（合计 3-4 批次，
  均为低风险标准化收益）
- **决策点后置**：~~契约网关自研 vs APISIX（阶段 4 时）~~ **已定案走框架
  （APISIX，2026-11-24）**；契约生成器注解化（随契约化批次）
- **明确保留**：servicehttp（平台契约核心）、实时层、安全语义族、薄件族
  ——这些的"自研"是业务语义沉淀而非重复造轮子
