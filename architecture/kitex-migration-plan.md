# ppbChat 微服务架构改造——Kitex 风格完整方案

> 版本：v1.0 · 日期：2026-11-22
> 范围：5 服务（im/file/iam/camera/gateway）+ 基础设施（etcd）
> 目标：服务注册发现 + 客户端负载均衡 + 自动容错（重试/熔断/超时预算）

---

## 一、目标架构

### 改造前（当前）

```
┌────────┐  HTTP   ┌────────┐  HTTP   ┌─── im :9112 ───┐
│客户端   │ ──────→ │ 网关    │ ──────→ │   (静态 IP)     │
└────────┘  :8080  └────────┘          └────────────────┘
                                        ↑
                          file ─ gRPC ──┘ (yaml 填 IP 直连)
                          camera ─ gRPC ─→ iam:9107 (静态)
                          无重试、无熔断、无服务发现
```

### 改造后（Kitex 风格）

```
┌────────┐  HTTP   ┌────────┐  gRPC   ┌─── im :9102 ────┐
│客户端   │ ──────→ │ 网关    │ ─────→ │  Kitex Server   │ ←──┐
└────────┘  :8080  │Kitex客户端│        │  + 注册到 etcd  │    │
                    └────────┘         └────────────────┘    │
                                         ↑                    │
                 ┌── file :9104 ──────┐  │                    │
                 │  Kitex Server      │──┘ (自动发现 im)      │
                 │  + 注册到 etcd     │                       │
                 └────────────────────┘                       │
                                                          ┌── etcd ──┐
                 ┌── iam :9107 ───────┐                    │ 服务注册   │
                 │  Kitex Server      │ ←──────────────────│ 自动发现   │
                 │  + 注册到 etcd     │ ←──────────────────│ 健康摘除   │
                 └────────────────────┘                    └──────────┘
                                                          ↑
                 ┌── camera :9106 ─────┐                  │
                 │  Kitex Server      │ ←─────────────────┘
                 │  + 注册到 etcd     │
                 └────────────────────┘

  所有服务间调用：自动负载均衡 + 自动重试 + 超时预算 + 熔断
  单端口：每个服务只开一个 gRPC 端口（HTTP 健康检查走 gRPC 协议）
```

## 二、关键设计决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| RPC 框架 | **Kitex**（gRPC 模式） | 字节开源，天然支持 Protobuf，不重写 proto |
| 注册中心 | **etcd** | Kitex 官方一等支持，K8s 生态标配 |
| 协议 | **保留 Protobuf** | 7 个 proto 文件、150+ 方法不改，仅重新生成 Kitex stub |
| 迁移策略 | **逐服务** | 一个服务一个阶段，每步可验证可回退 |
| 端口 | **单端口** | gRPC + Kitex 健康检查协议，去掉 HTTP 端口 |
| 网关 | **改造为 Kitex 客户端** | 从 HTTP 反代改为 gRPC 调用后端 |

## 三、逐服务改造清单

### 3.1 ppb-chat / service-im

**服务端改造：**

| 文件 | 改动 |
|---|---|
| `cmd/server/boot_wire.go` | `grpc.NewServer` → Kitex server；5 个 Register 改为 Kitex 服务定义 |
| `cmd/server/main.go` | 连接建立改为 Kitex client；删除 httpPort 监听 |
| `internal/transport/im/*.go` | Handler 签名从 gRPC 标准改为 Kitex 生成接口 |
| `internal/config/im_config.go` | 删 httpPort；加 etcd 地址配置 |

**客户端改造（im 调用 iam/file）：**

| 文件 | 改动 |
|---|---|
| `cmd/server/main.go` | iamConn/fileConn 改为 Kitex client（服务名发现） |
| `internal/client/grpc/iam/` | 适配器接口重写 |
| `internal/client/` | 所有引用 grpc.ClientConn 的地方改 Kitex client |

**测试改造：**

| 文件 | 改动 |
|---|---|
| bufconn 测试（~6 个） | 改为 Kitex 进程内测试 |
| e2e 测试 | 增加 etcd fixture |
| 集成测试 | mock 从 gRPC 改 Kitex |

### 3.2 ppb-file / service-file

**服务端：**
- `cmd/file/boot_wire.go`：FileService 注册改 Kitex
- `cmd/file/main.go`：三条出站连接（im/mail/iam）改 Kitex
- `cmd/file/file_config.go`：删除 health_port

**客户端适配器：**
- `internal/client/grpc/im/`：3 个适配器重写
- `internal/client/grpc/iam/`：重写
- `internal/client/grpc/refaccess/`：重写

**HTTP 端点迁移：**
- `internal/transport/file/file_transfer_http.go`（334 行）：上传/下载/缩略 → Kitex streaming RPC
- `internal/transport/file/group_file_http.go`：群文件 7 个端点 → gRPC handler
- 这些是**最大的单文件改动**，需要逐方法翻译

### 3.3 ppb-iam / service-iam

- `cmd/server/boot_wire.go`：多个 gRPC 服务改 Kitex
- `cmd/server/main.go`：imConn 改 Kitex
- `cmd/server/member_auth_wire.go`：svcauth 验证器适配 Kitex 传输层

### 3.4 ppb-camera / service-camera

- `cmd/server/boot_wire.go`：改 Kitex（最简单的服务）
- `cmd/server/main.go`：iamConn 改 Kitex

### 3.5 ppb-gateway / service-gateway

**最大改动**——从 HTTP 反向代理改为 gRPC 客户端：

| 文件 | 改动 |
|---|---|
| `internal/proxy/transparent.go`（144 行） | **重写**：HTTP handler → 调 Kitex client → 转发响应 |
| `internal/config/` | 删 httpAddress，改用服务名 + etcd |
| `cmd/gateway/main.go` | 所有上游连接改 Kitex |

**替代方案**（降低网关改动）：网关保持 HTTP，但增加 HTTP→gRPC 转码层（grpc-gateway）。
→ 保守方案，网关零改动，每个服务加 grpc-gateway 注解。

### 3.6 contracts 重新生成

| 契约仓 | proto 文件 | Kitex 生成 |
|---|---|---|
| contracts-im | 3 个（109 方法） | 重新生成 Kitex stub |
| contracts-file | 1 个 | 同上 |
| contracts-iam | 1 个 | 同上 |
| contracts-camera | 1 个 | 同上 |
| 总计 | 6 个 proto | 全部 Kitex 化 |

## 四、基础设施改造

### 4.1 etcd 部署

```yaml
# infra/docker-compose.yml 追加
  etcd:
    image: quay.io/coreos/etcd:v3.5.12
    container_name: ppb-etcd
    command: etcd --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://etcd:2379
    ports: ["2379:2379"]
    volumes: [ppb-etcd-data:/etcd-data]
    restart: unless-stopped
```

### 4.2 每个 YAML 配置变更

```yaml
# 改前（现在的写法）
server:
  grpc_port: 9102
  http_port: 9112
grpc_dependencies:
  iam_service:
    address: 192.168.3.55:9107

# 改后
server:
  port: 9102                  # ← 唯一端口
registry:
  etcd:
    endpoints: ["etcd:2379"]  # ← 注册中心
grpc_dependencies:
  iam_service:
    service_name: "ppbchat/iam"  # ← 服务名，自动发现
```

## 五、执行阶段

### Phase 0：基础设施准备（0.5 天）

- [ ] 部署 etcd
- [ ] 验证 etcd 可用
- [ ] Kitex 代码生成工具链搭建

### Phase 1：contracts 全量 Kitex 化（1 天）

- [ ] contracts-im：3 个 proto 重新生成 Kitex stub
- [ ] contracts-file / iam / camera：同上
- [ ] 编译验证

### Phase 2：camera 试点（1 天）

选 camera 因为最简单（1 个服务、1 个依赖）

- [ ] boot_wire.go 改 Kitex server + 注册 etcd
- [ ] main.go 改 Kitex client（调 iam）
- [ ] 删除 HTTP 端口
- [ ] 测试通过
- [ ] 真机联调

### Phase 3：iam 改造（2 天）

- [ ] 服务端 Kitex 化
- [ ] 客户端（调 im）Kitex 化
- [ ] svcauth 适配
- [ ] 测试 + 联调

### Phase 4：file 改造（3 天，HTTP 端点迁移是难点）

- [ ] 服务端 Kitex 化
- [ ] 客户端（调 im/mail/iam）Kitex 化
- [ ] **file_transfer_http.go → Kitex streaming RPC**（最大改动）
- [ ] **group_file_http.go → gRPC handler**
- [ ] 测试 + 联调

### Phase 5：im 改造（3 天，服务最多）

- [ ] 5 个 gRPC 服务 Kitex 化
- [ ] 客户端（调 iam/file）Kitex 化
- [ ] 实时 WS 适配
- [ ] 测试 + 联调

### Phase 6：gateway 改造（2 天）

- [ ] 上游连接改 Kitex
- [ ] HTTP 反代 → gRPC 调用（或保留 HTTP + grpc-gateway）
- [ ] 路由表适配
- [ ] 全链路联调

### Phase 7：端到端验收（1 天）

- [ ] 全部测试通过（单测 + 集成 + e2e）
- [ ] Docker Compose 多副本验证
- [ ] 服务摘除/恢复验证
- [ ] 性能对比

## 六、总工期与风险

| 阶段 | 工期 | 累计 |
|---|---|---|
| P0 基础设施 | 0.5 天 | 0.5 天 |
| P1 契约生成 | 1 天 | 1.5 天 |
| P2 camera | 1 天 | 2.5 天 |
| P3 iam | 2 天 | 4.5 天 |
| P4 file | 3 天 | 7.5 天 |
| P5 im | 3 天 | 10.5 天 |
| P6 gateway | 2 天 | 12.5 天 |
| P7 验收 | 1 天 | **13.5 天** |

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| Kitex Protobuf 兼容性 | 中 | 高 | P2 先试点 camera 验证 |
| HTTP 端点迁移遗漏 | 中 | 中 | 逐方法核对 + 集成测试 |
| 网关重写引入 bug | 高 | 高 | 备选：保留 HTTP 网关 + grpc-gateway |
| etcd 单点 | 低 | 高 | 开发态单节点够用，生产 3 节点 |

## 七、回退方案

- 每个阶段独立分支，可逐阶段回退
- 旧 gRPC 代码保留在 `legacy/` 分支
- Docker Compose 可一键切回旧配置（backup-legacy/）
- etcd 停掉后各服务退化为直连模式（Kitex 支持 static resolver）

---

*本文档基于 Kitex v0.5.x + etcd v3.5 开源版本。执行前建议先跑通 P2 camera 试点再全量推进。*
