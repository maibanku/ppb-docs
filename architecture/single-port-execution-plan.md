# 单端口改造执行计划（四服务收敛为纯 RPC 单口）

> 日期：2026-11-24 · 依据：`single-port-analysis.md`（路径 A 定案）+ `http-face-convergence-plan.md`（阶段 0）
> 目标：四服务各只留 RPC 口（910x），HTTP 翻译全部收口网关；可分级达成（见 §6）

## 阶段总览（依赖顺序，各自独立可回退）

```
阶段0 HTTP面契约化(已有计划) ──┐
阶段1 文件对象存储直传 ─────────┼→ 阶段4 网关契约化上收 + 服务删 HTTP 口
阶段2 WS 独立接入(或决策保留) ──┤      （探针走 gRPC health）
阶段3 OIDC 随门户(或决策保留) ──┘
```

## 阶段 1：文件传输改对象存储直传（3-4 天，独立收益最大）

**现状**：file HTTP 面车道 5 端点（upload multipart / chunk init / chunk /
download Range / thumb）+ 群文件 upload/download——文件字节流经服务进程。
MinIO backend 已在用（`storage.backend: minio`）。

**改造**：
1. proto：FileService 增 3 方法——`PresignUpload`（scene 白名单+配额预检→
   返回预签名 PUT URL+uploadId）、`PresignDownload`（fileId→预签名 GET URL）、
   `CommitUpload`（完成确认→登记元数据/配额记账/触发缩略生成）
2. 客户端（桌面 Rust `upload_file/download_file` + 移动端）：两步链——
   ①经网关调签发 RPC ②PUT/GET 直传 MinIO（预签名短时效）
3. 分片上传：S3 multipart 分段预签名替代自研 chunk 协议
4. 缩略图：Commit 时异步生成 `_thumb` 对象；缩略请求 = 预签名 thumb 键
5. 删除：`file_transfer_http.go` 全部 5 车道 + 群文件 2 车道 + 存储带宽出服务

**风险**：MinIO 直连网络可达性（客户端→192.168.3.55:9000）；断点续传语义
重述；配额预扣-确认窗口的对账兜底。

## 阶段 2：WS 独立接入（2-3 天，或务实跳过）

**现状**：im HTTP 面 9112 承载 `/ws`（网关 `ws: im` 透传升级）；在线路由表/
推送通道在 im 进程（Redis route.Publisher 已支持跨副本）。

**选项 A（单口达标）**：独立 realtime 接入进程——终结 WS、复用 Redis 路由表
与频道协议、上行转 im RPC。im 变纯 RPC。联调面大（实时性回归）。
**选项 B（务实）**：im 保留「RPC + WS」双口，登记决策——单端口达成 3/4。
本计划推荐先 B 后 A（B 不阻塞阶段 4 的其余三家）。

## 阶段 3：OIDC/认证端点处置（1-2 天）

**现状**：iam HTTP 面两类——bind/reply 认证端点（login/session/
oidc-exchange，可随阶段 4 上收）与 OIDC 协议端点（authorize/token/jwks，
浏览器重定向语义）+ federation binding。

**选项 A**：OIDC 端点随 iam-web 门户部署（门户 BFF 化）→ iam 单口达标
**选项 B**：iam 保留「RPC + OIDC」双口（端点少且稳定）

## 阶段 4：网关契约化上收 + 服务删 HTTP 口（3-4 天）

1. 网关改造：`httputil.ReverseProxy` 透传 → 契约网关——加载 7+ 份
   `api/*-http.json` + svcauth 中间件链（member/manage/subject）+
   servicehttp 引擎 + **kitex client（etcd 发现直调 910x）**
   > **2026-11-24 定案：网关实现使用框架（APISIX），不自研。** 上文「进程内
   > servicehttp + kitex client」为原自研方案描述，保留作对照；落地形态 =
   > 契约 JSON 经生成器转译为 APISIX 路由/grpc-transcode 配置 + ext_authz
   > 鉴权外挂（薄 Go 服务）+ 信封映射插件化承接。已并入 main 的网关翻译
   > 模式（D3–D6）为过渡形态。详见 framework-replacement-assessment §二.3。
2. 服务侧删除：HTTP 端口与 `*_wire.go` HTTP 装配、mux 挂载、config
   `http_port` 键；契约 JSON 文件搬至网关仓（或网关按服务加载）
3. 探针：`/ping`/`/healthz` → gRPC health 协议（internalauth 豁免前缀已
   预留）；`/metrics` → 网关聚合或各服务经 RPC 暴露
4. 网关成为契约+鉴权单点：补高可用考量（双实例 + etcd/路由无状态化）

## 验收

- [ ] etcd 四键不变；网关全 136 路由回归（响应快照 diff 零差异）
- [ ] 桌面/移动全功能回归（登录/消息/群文件/上传下载/通话）
- [ ] 服务进程监听口 = 各 1（lsof 实证）；deploy config 无 http_port
- [ ] 网关双实例压测通过（契约翻译路径无单点瓶颈）

## 总账

| 形态 | 内容 | 工作量 |
|---|---|---|
| **L2 务实**（推荐先达） | file/camera/iam（或 im）单口，其余留特殊口 | 7-9 天 |
| **L1 全量** | 四服务全单口（阶段 2/3 均选 A） | 10-12 天 |

每阶段独立分支独立收益（阶段 1 的带宽卸载单独就值回票价）；L1/L2 选择
可在阶段 4 前按当时团队带宽决定。
