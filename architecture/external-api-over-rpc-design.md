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


## 七、grpc-gateway 机制深析：如何做到 HTTP 层零 DTO/VO、零重复方法

> 触发问题：不想在 HTTP 层再写一层 DTO/VO 和方法（重复定义）。grpc-gateway 的
> 答案：**proto 是唯一事实源，HTTP 层的一切都是生成物**。

### 7.1 类型零重复——HTTP JSON 就是 proto 消息的规范投影

请求进来按注解填充**proto request 类型本身**，响应直接 protojson 序列化
**proto response 类型本身**。没有 HTTP DTO/VO——因为不存在第二种类型定义：
JSON 字段名（camelCase）、int64 字符串化、bytes base64、oneof 形状全部由
protojson 规范决定。校验也归一（`field_behavior=REQUIRED` / buf validate 注解）。

### 7.2 方法零重复——handler 是生成的反向代理

proto 方法上打注解，生成器产出 handler，而非手写：

```proto
rpc GetAnalysis(GetAnalysisReq) returns (GetAnalysisResp) {
  option (google.api.http) = {
    get: "/api/v1/camera/analysis/{task_id}"
  };
}
```

生成物的四步固定逻辑：解析 path/query/body → `PopulateFieldFromPath/JSON`
填充 proto req → 经 gRPC client 调**同一方法** → `ForwardResponseMessage`
（protojson 回写 + gRPC 状态码→HTTP 状态映射）。OpenAPI 文档也从同一注解
生成——**一次定义，RPC/HTTP/文档三处受益**。

### 7.3 对照我们：零重复诉求已满足，剩余差距只有「手写 vs 生成」

| 维度 | grpc-gateway | 我们现状 |
|---|---|---|
| 类型重复 | 无（protojson 直投） | **无**——servicehttp.Bind/Reply 直接操作 contracts proto 类型，从未有过 DTO/VO 层 |
| 方法重复 | 无（生成 handler） | 无（NewHandler 按契约 JSON 装配，无手写 handler） |
| 路由定义 | proto 注解（编译期生成） | **手写契约 JSON**——`bindings:{taskId:{field:task_id}}` 即 `{task_id}` 路径模板的等价物 |
| 翻译引擎位置 | 网关/独立进程 | 各服务 HTTP 面（路径 A 上收前的现状） |

即：重复定义的问题我们**从未发生**；与 grpc-gateway 的差距只在契约是手写
JSON（有漂移空间，目前由严格解析门禁 + contracts review 兜底）。

### 7.4 诚实边界：grpc-gateway 模式做不到的事

- JSON 形状不可任意定制（客户端适配 protojson 规范形状，不能自定义 VO 命名/
  投影——要 VO 就是 BFF 的活）；可经 `response_body` 做顶层裁剪
- 错误形状默认 gRPC status JSON；我们用 BaseResp 信封，若切换需自定义 error
  handler 映射（或客户端改契约——不建议）
- multipart/流式/WS 不在注解体系内（file_transfer 车道即此类，永远直转）

### 7.5 行动项（消最后的手写）

写小型生成器：读 proto 的 `google.api.http` 注解 → 生成 `api/*-http.json`
（servicehttp 引擎不变）→ 手写契约归零，实现「内部 RPC 定义 = 外部 HTTP 接口」
完全同源。工作量约 1 天；可与 contracts review 流程衔接（注解变更即接口变更，
评审可见）。


## 八、契约统一后的两个关键设计：前台/后台区分 与 匿名放行

### 8.1 前台 vs 后台的区分——三层机制（从粗到细）

**第一层：面文件**（contracts 仓 api/ 目录内物理分文件）

| 面 | 文件 | 面向 | 鉴权语义 |
|---|---|---|---|
| 前台-member | `member-http.json` | 桌面/移动端登录用户 | 验「你是谁」（member JWT → operator 注入） |
| 前台-public/subject | `public-http.json` / `subject-http.json` | 未登录引导/设备主体 | 匿名白名单或独立主体链 |
| 后台-manage | `manage-http.json` | 管理台运营人员 | 验「你是谁 **+ 你有什么权限**」（manage JWT + guard 逐方法 RBAC） |

**第二层：URL 前缀**（网空间物理分区）

```
前台：/api/v1/<service>/**          （member/public/subject 三面）
后台：/api/v1/manage/<service>/**   （manage 面，独立前缀独立挂载）
```
网关按前缀分流；后台前缀可加部署级约束（仅内网段/管理台域名来源）。

**第三层：v2 security 块**（引擎按声明挂链，路由级精确）

```json
"security": {
  "identity": "member"                        // 前台用户面
}
"security": {
  "identity": "manage",                       // 后台管理面
  "policy": { "app": "camera", "perm": "camera.overview.read" }  // 仅后台有 policy
}
```
结构性差异固化在 schema：**policy 字段只允许出现在 identity=manage 的路由上**
（校验器强约束——前台永不携带权限码声明）。

### 8.2 无需认证的接口怎么放行

**现状机制盘点**：三种已验证形态——
1. 整面匿名：`public-http.json`（identity=anonymous，登录/发码 4 条）
2. 面内白名单：camera subject 面的 `cameraAnonWhitelist`——**method+path 精确键**
   （`"POST /api/v1/camera/guest-sessions"` 等 4 条），白名单外必须带主体 token
3. manage 面治理拒绝段（governanceDenied）——后台的反向例外

**v2 统一设计**（匿名是显式声明而非缺省）：

```json
"security": {
  "identity": "anonymous",          // 形态 1：整面匿名
  "anonymous": true                  // 形态 2：面内路由级放行（等价 camera 白名单）
}
```

**放行的六条设计纪律（思考结论）**：

1. **默认拒绝，匿名必须显式声明**——`anonymous: true` 落在契约里，评审可见可追溯；
   不写就是必须认证（fail-closed 方向）
2. **精确键不放通配**——放行匹配 method+path 精确等值；带路径参数的路由
   （`/analysis/{taskId}`）禁止整段放行，防参数绕过
3. **匿名必须有安全补偿三件套**：网关限流（per-IP/per-path）＋服务端业务频控
   （如 CAM-4290 发码冷却）＋更高强度输入校验（无身份可追责 → 预检更严）
4. **匿名 ≠ 无鉴权，而是鉴权语义下放**——如 guest-sessions 是「签发凭据」的接口
   （产物是 token），templates 是公共内容；下游按方法语义裁决（camera 契约
   约定：白名单请求无 claims 不注入主体）
5. **后台匿名 = 结构性禁止**——v2 校验器强约束：identity=manage 的路由出现
   anonymous 即解析失败（防线写进 schema，不靠自觉）
6. **可观测补偿**——匿名接口审计记录 IP/UA/设备摘要（camera 的 client_hint
   即此用途），补偿身份缺失的追责能力
