# 从 gRPC 接口到 HTTP 暴露：编写流程指南（含前缀约定）

> 日期：2026-11-23 · 适用：现有 servicehttp 契约体系（零 DTO/VO）
> 关联：`external-api-over-rpc-design.md`（设计分析）、`kitex-placement-map.md`

## 前缀约定（相同服务前缀相同——已是事实约定，此处成文）

| 面 | 路径前缀 | 挂载点 | identity |
|---|---|---|---|
| 客户端面 | `/api/v1/<service>/**`（camera `/api/v1/camera/`、im `/api/v1/im/`…） | 每服务一前缀一面（`mux.Handle("/api/v1/camera/", subjectFace)`） | member / camera-subject / anonymous |
| 管理面 | `/api/v1/manage/<service>/**` | `/api/v1/manage/` 前缀的 manage face | manage |

一服务一前缀：网关按前缀选 upstream；契约 JSON 的 `identity`/`operator`/`policy`
决定中间件链（验 token → 注 operator/subject → app_perm 策略）。**新接口必须落
在所属服务的前缀下**，不允许跨服务前缀定义路由。

## 编写流程（示例：camera 新增「查询我的分析历史」）

需求：`GET /api/v1/camera/analyses?limit=20` → 新 RPC
`camera.CameraService/ListAnalyses`。

### 第 1 步：proto 定义（唯一事实源）

contracts-camera/proto/camera.proto：

```proto
// ListAnalyses 查询主体分析历史（客户端接口）。
rpc ListAnalyses(ListAnalysesReq) returns (ListAnalysesResp) {
  // 演进后（注解生成器落地）：此注解即第 4 步契约的生成源
  option (google.api.http) = { get: "/api/v1/camera/analyses" };
}
message ListAnalysesReq {
  int32 limit = 1;  // 页大小（≤50，缺省 20）
}
message ListAnalysesResp {
  common.BaseResp base = 1;
  repeated AnalysisBrief items = 2;
}
```

字段规范沿既有契约约定（十进制 id 串、RFC3339 时间、错误只走 BaseResp 信封）。

### 第 2 步：生成类型

contracts 仓 `buf generate` → `gen/go/camera`（proto.Message + getter，HTTP 与
RPC 共用同一类型——**没有 DTO/VO**）；服务仓重生成 kitex 服务组（方法表 +1）。

### 第 3 步：服务端实现（唯一的业务代码）

service-camera `internal/transport/camera/camera_kitex.go`：

```go
// ListAnalyses 分析历史（主体归属）。
func (h *CameraServiceHandler) ListAnalyses(ctx context.Context, req *pb.ListAnalysesReq) (*pb.ListAnalysesResp, error) {
    p, base := RequirePrincipal(ctx, "ListAnalyses")
    if p == nil {
        return &pb.ListAnalysesResp{Base: base}, nil
    }
    items, bizErr := h.analysis.ListOf(ctx, p.SubjectID, req.GetLimit())
    if bizErr != nil {
        return &pb.ListAnalysesResp{Base: baseRespOf(bizErr)}, nil
    }
    return &pb.ListAnalysesResp{Base: baseRespOf(nil), Items: items}, nil
}
```

编译期断言（`var _ pb.CameraService = ...`）自动覆盖新方法。

### 第 4 步：HTTP 契约一条路由（零 handler 代码）

`api/subject-http.json` routes 追加：

```json
{ "method": "GET", "path": "/api/v1/camera/analyses",
  "rpc": "/camera.CameraService/ListAnalyses",
  "operator": "",
  "request": "camera.ListAnalysesReq",
  "response": "camera.ListAnalysesResp",
  "bindings": {} }
```

- query 参数按 proto 字段名自动绑定（`?limit=20` → `limit` 字段）
- `bindings` 只需写 **path 参数**映射：`"/api/v1/camera/analysis/{taskId}"` →
  `{"taskId": {"field": "task_id", "kind": "string"}}`
- 管理面路由另加 `"policy": {"kind": "app_perm", "appKey": "camera",
  "perm": "camera.xxx.read"}`（authzguard 链消费）
- `NewHandler(contract, invoker)` 装配即获得该路由——**无任何手写 HTTP 方法**

### 第 5 步：网关路由一行

ppb-base `deploy/config/gateway-routes.yaml`：

```yaml
- { method: GET, path: "/api/v1/camera/analyses", upstream: camera }
```

### 第 6 步：鉴权——不用写

subject 面由 `identity` + CameraSubjectAuth 链按面统一裁决（验主体 token →
注入 `x-ppb-subject` → 服务端 RequirePrincipal 消费）；member/manage 面各走
对应 svcauth 链。新路由只要落在正确的面（契约文件），鉴权自动继承。

### 第 7 步：验证

服务起服（严格解析 + deploy 兼容门禁兜底契约 typo）→ 契约/行为测试 →

```bash
curl -H "Authorization: Bearer <主体 token>" \
  'http://<gw>:8080/api/v1/camera/analyses?limit=20'
```

链路：网关透传 → 服务 HTTP 面 Bind（protojson）→ 回环/kitex RPC →
ListAnalyses → Reply 信封。

## 第 8 步（演进态）：注解生成器

第 1 步的 `google.api.http` 注解 + `make gen-api` 生成第 4 步契约 JSON——
流程收敛为「proto 注解 → 生成契约」两步，手写 JSON 归零（见
external-api-over-rpc-design.md §7.5）。

## 速查：改动面清单

| 改什么 | 哪里 | 类型 |
|---|---|---|
| RPC 方法 + 消息 | contracts proto | 定义 |
| Go 类型 + kitex 服务组 | buf/kitex 生成 | 生成 |
| 业务实现 | transport *_kitex.go | **唯一业务代码** |
| HTTP 路由 | api/*-http.json 一条 | 声明 |
| 网关分流 | gateway-routes.yaml 一行 | 声明 |
| DTO/VO/HTTP handler | —— | **不存在** |
