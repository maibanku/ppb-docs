# 外部接口设计分析：内部全部走 RPC 后，对外 API 怎么写

> 日期：2026-11-23 · 触发问题：内部通信全部 RPC 化后，对接外部（桌面/移动/管理台）的接口如何编写与设计
> 关联：`single-port-analysis.md`（路径 A 的前置）、`adr-gateway-http-proxy.md`（现状定案）

## 一、业界三层标准形态

```
客户端 ──HTTP/JSON──> 网关（协议翻译 + 边缘策略）──RPC──> 纯 RPC 服务
                    └─(端聚合需求时)─> BFF（Backend-for-Frontend）──RPC──> 多个 RPC 服务
```

外部接口的「写法」全部集中在网关与 BFF 层；业务服务只写 RPC。

## 二、两种写法流派

### 流派 1：声明式（IDL 注解 → 生成绑定）——字节内部主力

- 接口定义 = 在 Thrift IDL 上打 HTTP 注解（path/method/参数源/鉴权要求），
  API 平台从注解生成网关绑定：参数校验、类型转换、错误映射全自动
- 开源等价物：
  - **grpc-gateway**（gRPC 生态标准）：proto 打 `google.api.http` 注解 →
    生成 HTTP/JSON ↔ gRPC 反代
  - **Hertz hz 工具**（CloudWeGo）：IDL 注解生成 HTTP handler 骨架
- 适合：透传型接口（一 HTTP 调一 RPC，无跨服务聚合）——占绝对多数

### 流派 2：命令式（BFF 手写 handler）

- Hertz/gin 手写：解析请求 → 编排多个 RPC → 裁剪/聚合响应
- 适合：端形态强异构的聚合接口（Feed 流、工作台首页）
- 字节实际是混合：透传型走声明式网关，重聚合走 BFF

## 三、外部接口设计的五个关键面（无论流派都要定）

1. **契约定义**：路由 → RPC 映射、参数绑定（path/query/body → proto 字段）、
   响应投影
2. **鉴权模型**：边缘验外部凭证（token/设备凭证）→ 转内部信任凭据（内部
   共享 token + 按方法断言）；「外不信、内信」的边界画在网关
3. **错误映射**：RPC 业务信封（BizCode/Message/HttpStatus）→ HTTP 状态码 +
   统一 JSON code 结构；成功口径（空码=200）两侧一致
4. **特殊语义车道**：WS / multipart / OIDC 重定向不能 bind/reply 化——
   独立安置（见 single-port-analysis 三个前置）
5. **版本化**：外部契约独立演进（/api/v1），内部 RPC 自由重构；契约变更
   走 review（我们的 contracts 仓 + tag 流程）

## 四、映射到我们：资产盘点与目标形态

**我们已事实上拥有一套声明式外部接口系统，只是宿主在各服务进程内：**

| 组件 | 现有资产 | 位置 |
|---|---|---|
| 契约定义 | 7 份 JSON（`path/{param}`、`rpc`、`request/response`、`bindings` 参数绑定）——**grpc-gateway 注解的手写等价物** | 各服务 `api/*-http.json` |
| 翻译引擎 | `servicehttp.Bind`（JSON/path/query→proto.Message）+ `Reply`（protojson 信封） | ppb-base 共享库 |
| RPC 调用 | `Invoker` 抽象——当前回环 grpc-go `LocalConn`，**可无痛换 kitex client + etcd 发现**（Phase C 出站件已验证） | ppb-base + 各服务 |
| 鉴权插件 | svcauth 中间件族（member/manage/subject 三面 + 断言承接） | ppb-base + 各服务装配 |

**因此答案：内部全 RPC 后，外部接口的写法 = 同一套声明式契约，把宿主从
各服务搬进网关。** 目标形态：

```
桌面/移动 ──HTTP──> 网关（加载 7 份契约 JSON）
                      ├─ servicehttp.Bind/Reply（翻译）
                      ├─ svcauth 中间件链（验 token → 签内部凭据+断言）
                      └─ kitex client（etcd 发现）──RPC──> 四个纯 RPC 服务
                   特殊车道：WS/multipart/OIDC 仍透传（三前置完成前）
```

新增一个外部接口的工作量变为：contracts 加 RPC 方法 + 契约 JSON 加一条路由
（未来可演进为 proto 注解自动生成 JSON），服务侧零 HTTP 代码。

## 五、与字节的差异与演进项

| 维度 | 字节 | 我们现状 → 演进 |
|---|---|---|
| 契约来源 | IDL 注解编译期生成 | 手写 JSON → 可上 proto `google.api.http` 注解生成（消手写、防漂移，与 contracts review 流程衔接） |
| 翻译宿主 | API 网关/BFF | 各服务 HTTP 面 → 路径 A 上收网关（single-port 前置齐备后） |
| 聚合层 | BFF（按端） | 暂无需求；桌面/移动接口若需跨服务聚合再引入（新 Go 服务复用 kitex 出站件即可） |
| 鉴权边界 | 网关插件 | svcauth 上收后同构：外部凭证在网关止步，内部凭据+断言下传 |

## 六、结论

「内部全部走 RPC」后外部接口不是重写，而是**搬家 + 自动化**：契约从各服务
的 JSON 上收到网关（翻译引擎与鉴权中间件都是 ppb-base 共享件，随迁即可），
长期演进方向是 proto 注解生成契约（grpc-gateway 模式）。当前两端口架构下，
这套写法已经在运行——每份 `api/*-http.json` 就是一条外部接口的全部定义。
