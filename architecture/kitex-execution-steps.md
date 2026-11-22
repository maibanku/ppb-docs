# ppbChat Kitex 改造——逐服务精确执行步骤

> 日期：2026-11-22 · 执行模式：逐服务渐进 · 每步可验证可回退
> 前置文档：`architecture/kitex-migration-plan.md`（总体方案）

---

## 执行实录（2026-11-23，P1 camera 试点落地）

P1 已按下述**落地修正方案**完成并验证（ppb-camera@c4f0dce），后续服务同模式复制：

| 项 | 实际落地 | 与上文原步骤的差异 |
|---|---|---|
| 服务端 | `server.NewServer` 默认传输（netpoll + **detection 协议探测**），同口继续承载**标准 gRPC 线缆** | 无需 `WithTransportProtocol`——Kitex v0.16 服务端按连接自动识别 gRPC（HTTP/2 前缀探测后交 nphttp2 处理器） |
| 类型面 | 处理器签名切 `kitex_gen/`（**prutal** 类型）；prutal 为反射式 protobuf 序列化，对内嵌 gen/go `common.BaseResp` 混生树兼容 | 原文「签名不变仅换 import」成立；`Unimplemented*Server` 内嵌删除 |
| 互通 | **grpc-go 客户端 × Kitex 服务端线缆级互通**（HTTP 面回环 LocalConn、未迁移直连方零改动）：metadata（HTTP/2 头 → `nphttp2/metadata.FromIncomingContext`）、gRPC 状态码（`nphttp2/status.Err` 保真 Unauthenticated/PermissionDenied）、grpc-timeout 透传 | 迁移可**逐服务独立进行**，不要求两端同时切换 |
| 中间件 | ppb-base `rpcx/kitexmw`（Recovery/RequestID/InternalAuth + FullMethodFromContext）与 `rpcx/kitexstarter`（boot 组件，组件名沿用 "grpc" 保停机序口径），tag `go-framework/rpcx/v0.2.0` | 拦截器判定逻辑零复制（复用 interceptor.Token/Exempt、requestid 本体） |
| 注册 | `kitex-contrib/registry-etcd`：config `registry.etcd.endpoints` 非空才注册（发现名 `ppbchat-<svc>`，etcd key `kitex/registry-etcd/<svc>/<lan-ip>:<rpc-port>`，lease keepalive + 停机反注册实测通过） | etcd 以二进制常驻 127.0.0.1:2379（Docker 镜像源不可达，见 infra 记录） |
| 验证 | 全量测试 15 包 ok/0 FAIL；**测试装配用真实 127.0.0.1:0 回环 TCP**（bufconn 不可用：gonet 传输与 nphttp2 处理器不兼容——serveConn 循环 nil-deref，且 detection 探测依赖 netpoll.Reader）；实机冒烟 templates API 全链路 + etcd 注册/摘除 | 原 1.7 验收口径全部命中 |

**有意差异**：gRPC reflection 随 server 替换退役（grpcurl 内省改走 proto 契约文件）。

**后续阶段**（本文 Phase 2-5 的服务端部分同模式复制后）：
- Phase C（未做）：出站内部调用 Kitex 客户端化（etcd resolver + 客户端负载均衡/重试/熔断替代 RETRY_CONFIG 静态 JSON）；当前出站仍为 grpc-go 直连（已带 retry/round_robin）。
- 网关维持 HTTP 反代不变（见「总体策略修正」）。

---

## 总体策略修正

经深度分析，**网关暂不重写**（136 条路由风险太高），采用分层改造：

| 层次 | 改不改 | 理由 |
|---|---|---|
| **内部 RPC**（服务间 gRPC） | ✅ 改为 Kitex | 收益最大（发现/容错/负载均衡） |
| **网关** | ❌ 暂不改 | 136 条路由，重写风险高，保持 HTTP 反代 |
| **HTTP 端口** | ✅ 保留 | 网关还需要它 |
| **proto** | ✅ 保留 | Kitex 支持 Protobuf，不重写 |

改造后每个服务**仍有两个端口**，但内部互调已具备完整容错能力。

---

## Phase 0：基础设施（0.5 天）

### 0.1 部署 etcd

```bash
# infra/docker-compose.yml 追加
```

```yaml
  etcd:
    image: quay.io/coreos/etcd:v3.5.12
    container_name: ppb-etcd
    environment:
      ETCD_NAME: ppb-etcd
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd:2379
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_INITIAL_ADVERTISE_PEER_URLS: http://etcd:2380
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_CLUSTER: ppb-etcd=http://etcd:2380
      ETCD_DATA_DIR: /etcd-data
    ports: ["2379:2379"]
    volumes: [ppb-etcd-data:/etcd-data]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 5s
      timeout: 3s
      retries: 20

volumes:
  ppb-etcd-data:
    external: false
```

### 0.2 添加 Kitex 依赖

```bash
# 每个服务的 go.mod 都要加
go get github.com/cloudwego/kitex@latest
go get github.com/cloudwego/kitex/pkg/registry
go get github.com/cloudwego/kitex/pkg/registry/etcd
go get github.com/cloudwego/kitex/pkg/discovery
go get github.com/kitex-contrib/registry-etcd@latest
```

### 0.3 验收

```bash
docker compose up -d etcd
docker exec ppb-etcd etcdctl put test "hello"
docker exec ppb-etcd etcdctl get test
# 预期输出：test / hello
```

---

## Phase 1：camera 试点（1 天）

### 为什么选 camera
- 只有 1 个 gRPC 服务（最小）
- 只调用 1 个依赖（iam）
- 13 个测试（最少的测试改动）

### 1.1 重新生成 Kitex stub

```bash
# contracts-camera/proto/camera.proto → Kitex 生成
cd contracts-camera
kitex_tool -type protobuf -service ppbchat-camera proto/camera.proto
# 输出到 kitex_gen/ 目录
```

### 1.2 服务端改造

**文件：`service-camera/cmd/server/boot_wire.go`**

```go
// 改前（现在的代码）
svr := grpc.NewServer(grpc.ChainUnaryInterceptor(
    recovery.GrpcUnaryInterceptor(),
    internalauth.UnaryServerInterceptor(),
    grpcrid.GrpcServerInterceptor(),
))
camera.RegisterCameraServiceServer(svr, handler)
lis, _ := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Server.RPCPort))
svr.Serve(lis)
```

```go
// 改后（Kitex 版本）
import (
    "github.com/cloudwego/kitex/server"
    kitexetcd "github.com/kitex-contrib/registry-etcd"
    "github.com/cloudwego/kitex/pkg/rpcinfo"
)

// etcd 注册器（全局一次）
etcdRegistry, err := kitexetcd.NewEtcdRegistry([]string{"etcd:2379"})
if err != nil {
    return fmt.Errorf("etcd registry: %w", err)
}

// Kitex 服务端（替代 grpc.NewServer）
svr := camerapb.NewServer(
    handler,                                    // 业务 handler（签名需适配）
    server.WithRegistry(etcdRegistry),          // ← 自动注册到 etcd
    server.WithServerBasicInfo(&rpcinfo.EndpointBasicInfo{
        ServiceName: "ppbchat-camera",          // ← 服务名（发现用）
    }),
    server.WithServiceAddr(&net.TCPAddr{
        Port: cfg.Server.RPCPort,
    }),
    // 中间件（替代 gRPC interceptor）
    server.WithMiddleware(recovery.Middleware),
    server.WithMiddleware(internalauth.KitexMiddleware),
)
svr.Run()
```

**handler 签名变化：**
```go
// 改前（gRPC 标准）
func (h *CameraHandler) AnalyzeImage(ctx context.Context, req *camera.AnalyzeImageReq) (*camera.AnalyzeImageResp, error)

// 改后（Kitex 生成接口——签名相同！Kitex Protobuf 模式保持方法签名不变）
// 唯一区别：import 路径从 gen/go/ 变为 kitex_gen/
func (h *CameraHandler) AnalyzeImage(ctx context.Context, req *camera.AnalyzeImageReq) (*camera.AnalyzeImageResp, error)
//  ↑ 方法签名不变，但 import 的是 kitex_gen 的类型
```

### 1.3 客户端改造

**文件：`service-camera/cmd/server/main.go`**

```go
// 改前
iamConn := grpc.NewClient(cfg.GrpcDeps.IAMService.Address, internalDialOpts()...)
iamClient := iam.NewIAMServiceClient(iamConn)

// 改后
import (
    "github.com/cloudwego/kitex/client"
    kitexetcd "github.com/kitex-contrib/registry-etcd"
)

etcdResolver, err := kitexetcd.NewEtcdResolver([]string{"etcd:2379"})
if err != nil {
    return fmt.Errorf("etcd resolver: %w", err)
}

iamClient, err := iam.NewClient(
    "ppbchat-iam",                              // ← 服务名（不是 IP）
    client.WithResolver(etcdResolver),          // ← etcd 自动发现
    client.WithLoadBalancer(&weight.RoundRobinWeightedBalancer{}),
    client.WithRPCTimeout(3 * time.Second),
    client.WithRetry(...),
    client.WithMiddleware(internalauth.KitexClientMiddleware),
)
```

### 1.4 业务适配器改造

**文件：`service-camera/internal/client/grpc/iam/` 下的所有文件**

```go
// 改前：接收 grpc.ClientConn
func NewIamClient(conn *grpc.ClientConn) *IamClient

// 改后：接收 Kitex client
func NewIamClient(cli iampb.IAMServiceClient) *IamClient
```

### 1.5 YAML 配置

```yaml
# 改前
grpc_dependencies:
  iam_service:
    address: 192.168.3.55:9107

# 改后
grpc_dependencies:
  iam_service:
    service_name: "ppbchat-iam"    # ← etcd 服务名
registry:
  etcd:
    endpoints: ["etcd:2379"]
```

### 1.6 测试改造

| 测试文件 | 改动 |
|---|---|
| `camera_config_test.go` | 配置断言更新（service_name 替代 address） |
| 业务测试 | mock 从 gRPC 接口改为 Kitex 接口（签名相同，import 不同） |
| e2e 测试 | 增加 etcd fixture（或用进程内 mock registry） |

### 1.7 验收标准

```bash
# 1. 编译通过
GOWORK=off go build ./...

# 2. 测试通过
GOWORK=off go test ./... # 13 包

# 3. etcd 注册验证
docker exec ppb-etcd etcdctl get --prefix "ppbchat-camera"
# 预期：能看到 camera 实例的 IP:Port

# 4. 服务间调用验证
# camera 调用 iam 正常（从 etcd 发现 iam 地址）

# 5. 网关 API 正常（HTTP 端口未变）
curl http://localhost:8080/api/v1/camera/templates
```

---

## Phase 2：iam 改造（2 天）

### 2.1 服务端改造

**文件：`service-iam/cmd/server/boot_wire.go`**

改动同 camera 模式，但 iam 注册了多个 gRPC 服务：

```go
// 需要改的服务注册（所有 Register 调用都要 Kitex 化）
svr1 := iampb.NewIamServiceServer(handler1, opts...)
svr2 := iampb.NewAdminCompatServiceServer(handler2, opts...)
svr3 := iampb.NewOidcServiceServer(handler3, opts...)
// ... 所有服务
```

### 2.2 客户端改造

**文件：`service-iam/cmd/server/main.go`**

```go
// im 连接改 Kitex
imClient := im.NewClient("ppbchat-im", client.WithResolver(etcdResolver), ...)
```

### 2.3 特殊处理

| 事项 | 说明 |
|---|---|
| OIDC HTTP 端点 | **保留 HTTP**（OIDC 协议需要 HTTP redirect） |
| svcauth 验证器 | 适配 Kitex 传输层（`svcauth.NewValidator` 接口不变） |
| 管理面 | `manage_*.go` 的 gRPC 注册全部 Kitex 化 |

### 2.4 验收

同 Phase 1，额外验证 OIDC 登录流程完整。

---

## Phase 3：file 改造（3 天）

### 3.1 gRPC 服务端 + 客户端（同前两阶段模式）

### 3.2 HTTP 端点处理（关键决策）

| 端点 | 处理方式 |
|---|---|
| `/api/v1/file/upload` (multipart) | **保留 HTTP**（multipart 上传不适合 gRPC） |
| `/api/v1/file/download/{id}` | **保留 HTTP**（流式下载保留 HTTP 更简单） |
| `/api/v1/file/thumb/{id}` | **保留 HTTP** |
| `/api/v1/file/upload/chunk/*` | **保留 HTTP** |
| `/api/v1/file/groups/*` | **保留 HTTP** |

**决策：HTTP 端点全部保留，不做 gRPC 迁移。**

理由：
1. multipart/流式在 HTTP 上更成熟
2. 网关本来就是 HTTP 转发
3. 这些端点是外部 API，不是服务间互调
4. Kitex 改造只针对内部 gRPC 通信

### 3.3 内部 gRPC 调用改造

```go
// file 调用 im/iam/mail 的三条连接全部改 Kitex
imClient := im.NewClient("ppbchat-im", ...)
mailClient := mail.NewClient("ppbchat-mail", ...)
iamClient := iam.NewClient("ppbchat-iam", ...)
```

### 3.4 验收

```bash
# 群文件上传/下载正常（HTTP 端点未变）
# file → im 群文件鉴权正常（Kitex + etcd 发现）
# 配额/回收站正常
```

---

## Phase 4：im 改造（3 天）

### 4.1 服务端（5 个 gRPC 服务）

```go
// 需要注册的 5 个服务全部 Kitex 化
svr := im.NewServer(handler, ...)                    // IMService
svrOrg := orgcompat.NewServer(handlerOrg, ...)       // OrgCompatService
svrRef := refaccess.NewServer(handlerRef, ...)       // RefAccessService
svrGrpAuth := groupfileauth.NewServer(handlerGA, ...) // GroupFileAuthService
svrChatOrg := chatorg.NewServer(handlerCO, ...)      // ChatOrgService
```

### 4.2 实时 WebSocket 适配

**注意：WS 走网关，不走服务间 gRPC，此阶段不受影响。**

### 4.3 客户端

```go
// im 调用 iam/file 改 Kitex
iamClient := iam.NewClient("ppbchat-iam", ...)
fileClient := file.NewClient("ppbchat-file", ...)
```

### 4.4 验收

全功能回归（消息收发/群文件/好友标签/通话）。

---

## Phase 5：收尾 + 全链路验收（1 天）

### 5.1 全量测试

```bash
# 四仓全部测试
for r in ppb-chat ppb-file ppb-iam ppb-camera; do
  cd $r/service-*/ && GOWORK=off go test ./...
done
```

### 5.2 多副本验证

```bash
# docker-compose.yml 设 replicas: 2
# 验证负载均衡（两个 im 实例轮流被调用）
```

### 5.3 服务摘除恢复

```bash
# 停掉一个 im 副本 → file 自动发现并切到另一个
# 恢复副本 → 自动回到负载池
```

---

## 执行时间线

| 天 | 内容 |
|---|---|
| D1 上午 | P0 etcd + Kitex 依赖 |
| D1 下午 | P1 camera 契约生成 + 服务端 |
| D2 | P1 camera 客户端 + 测试 + 验收 |
| D3-4 | P2 iam |
| D5-7 | P3 file |
| D8-10 | P4 im |
| D11 | P5 全链路验收 |
| **总计** | **11 天** |

---

*本文档按"每天可提交、每步可回退"设计。任一阶段失败不影响已完成阶段。*
