# ppbChat 服务配置统一模板（目标态结构）

> 本文件定义所有服务的标准配置结构。每个服务的实际配置文件是本模板的子集
> （只取它用到的部分）。层级和键名统一，新增服务照此追加。

---

## 完整结构总览（所有服务+基础设施）

```yaml
# ============================================================
# ppbChat 服务配置
# ============================================================

# ---- 基础设施（通用，所有服务可能引用）----
infrastructure:
  mysql:
    host: 192.168.3.55                    # MySQL 主机
    port: 3306                            # MySQL 端口
    username: root                        # 用户名（口令走环境变量 PPB_DB_PASSWORD）
    databases:
      im: ppb_im                          # IM 服务库名
      file: ppb_file                      # File 服务库名
      iam: ppb_iam                        # IAM 服务库名
      camera: ppb_camera                  # Camera 服务库名
      mail: ppb_mail                      # Mail 服务库名

  redis:
    address: 192.168.3.55:6379            # Redis 地址
    password: ""                          # 口令（走环境变量 PPB_REDIS_PASSWORD）
    database: 0                           # DB 编号

  minio:                                  # 对象存储（S3 兼容）
    endpoint: 192.168.3.55:9000           # API 端点
    console_port: 9001                    # 管理界面端口
    access_key: ppbchat                   # 访问键（生产走环境变量）
    secret_key: ppbchat-minio             # 密钥（生产走环境变量）
    use_ssl: false                        # 内网 http=false
    buckets:
      file: ppb-file                      # 文件服务桶

  rabbitmq:                               # 消息队列（按需启用）
    url: amqp://ppbchat:ppbchat-mq@192.168.3.55:5672/
    enabled: false                        # 当前未部署

# ---- 内部 gRPC 服务注册表（谁提供什么服务、在哪个端口）----
grpc_services:
  im:                                     # 即时通讯服务
    name: ppbchat-im
    grpc_address: 192.168.3.55:9102       # gRPC 端口（服务间内部调用）
    http_address: 192.168.3.55:9112       # HTTP 端口（健康检查 /healthz）
    description: 消息路由/会话/群治理/好友/通讯录

  file:                                   # 文件服务
    name: ppbchat-file
    grpc_address: 192.168.3.55:9104
    http_address: 192.168.3.55: 9114      # HTTP 端口（/ping + 文件透传）
    description: 上传/下载/分片/配额/回收站/群文件

  iam:                                    # 统一认证中心
    name: ppbchat-iam
    grpc_address: 192.168.3.55:9107
    http_address: 192.168.3.55:9117       # HTTP 端口（OIDC + 会话端点）
    description: 用户注册/登录/OIDC/MFA/会话管理

  camera:                                 # 相机 AI 服务
    name: ppbchat-camera
    grpc_address: 192.168.3.55:9106
    http_address: 192.168.3.55:9116
    description: AI 图像分析/配额/用户同意

  mail:                                   # 邮件服务
    name: ppbchat-mail
    grpc_address: 192.168.3.55:9103
    http_address: 192.168.3.55:9113
    description: 邮件发送/附件
    enabled: false                        # 当前未部署

# ---- 网关 ----
gateway:
  listen_address: 0.0.0.0:8080            # HTTP 监听
  websocket_path: /ws                     # WebSocket 路径
  upstreams:                              # 转发目标（引用 grpc_services）
    im:
      grpc: 192.168.3.55:9102
      http: 192.168.3.55:9112
    file:
      grpc: 192.168.3.55:9104
      http: 192.168.3.55:9114
    iam:
      grpc: 192.168.3.55:9107
      http: 192.168.3.55:9117
    camera:
      grpc: 192.168.3.55:9106
      http: 192.168.3.55:9116

# ---- 前端入口 ----
frontend:
  iam_portal:                             # IAM 登录页
    url: http://192.168.3.55:8240/login
  manage_console:                         # 统一管理后台
    url: http://192.168.3.55:8210
```

---

## 各服务实际配置（子集示例）

### im.yaml（IM 服务——引用 iam + file + redis）

```yaml
# ============================================================
# ppbchat-im 即时通讯服务配置
# 描述：消息路由/会话/群治理/好友/通讯录
# ============================================================

# ---- 自身监听端口 ----
server:
  grpc_port: 9102                         # gRPC（file/camera/iam 调用我）
  http_port: 9112                         # HTTP（网关转发 + /healthz）
  cluster_name: ppbchat-im

# ---- 数据库（引用 infrastructure.mysql）----
database:
  mysql:
    host: 192.168.3.55
    port: 3306
    database: ppb_im
    # DSN 空 = 走 IM_DB_DSN 环境变量；再空 = SQLite 起步态
    dsn: ""

# ---- Redis（引用 infrastructure.redis）----
redis:
  address: 192.168.3.55:6379
  password: ""

# ---- 内部 gRPC 依赖（我要调用谁）----
grpc_dependencies:
  iam_service:                            # 统一认证中心
    address: 192.168.3.55:9107
    purpose: 管理授权 AdminAuthz 回源
  file_service:                           # 文件服务
    address: 192.168.3.55:9104
    purpose: 文件上传/录音存储

# ---- 日志 ----
log:
  level: info                             # debug | info | warn | error
```

### file.yaml（File 服务——引用 im + mail + iam + minio）

```yaml
# ============================================================
# ppbchat-file 文件服务配置
# 描述：上传/下载/分片/配额/回收站/群文件
# ============================================================

# ---- 自身监听端口 ----
server:
  grpc_port: 9104                         # gRPC（im 调用我）
  http_port: 9114                         # HTTP（网关转发 + /ping）
  http_bind: 0.0.0.0                      # 透传端点监听地址

# ---- 数据库 ----
database:
  mysql:
    host: 192.168.3.55
    port: 3306
    database: ppb_file
    dsn: ""                               # 空 = 走 FILE_DB_DSN 环境变量

# ---- 对象存储 ----
storage:
  backend: minio                          # local | minio | oss | s3
  root: data/files                        # local 后端根目录
  minio:
    endpoint: 192.168.3.55:9000
    bucket: ppb-file
    access_key: ppbchat
    secret_key: ppbchat-minio
    use_ssl: false

# ---- 内部 gRPC 依赖 ----
grpc_dependencies:
  im_service:                             # 即时通讯
    address: 192.168.3.55:9102
    purpose: 会话成员裁决/群文件鉴权/身份反查
  mail_service:                           # 邮件
    address: 192.168.3.55:9103
    purpose: CheckFileAccess 邮件参与方裁决
  iam_service:                            # 统一认证
    address: 192.168.3.55:9107
    purpose: 管理授权回源 + 成员会话复检

# ---- 日志 ----
log:
  level: info

# ---- 业务参数 ----
quota:
  default_bytes: 2147483648               # 个人配额 2GB
  group_file_default_bytes: 0             # 群空间默认（0=不限）
```

### iam.yaml（IAM 服务——引用 im）

```yaml
# ============================================================
# ppbchat-iam 统一认证中心配置
# 描述：用户注册/登录/OIDC/MFA/会话管理
# ============================================================

# ---- 自身监听端口 ----
server:
  grpc_port: 9107
  http_port: 9117

# ---- 数据库 ----
database:
  mysql:
    host: 192.168.3.55
    port: 3306
    database: ppb_iam
    dsn: ""

# ---- 内部 gRPC 依赖 ----
grpc_dependencies:
  im_service:
    address: 192.168.3.55:9102
    purpose: 成员资格复检/注册邀请

# ---- OIDC Provider ----
oidc:
  issuer_url: http://192.168.3.55:8080/iam    # 网关透传口径
  login_url: http://192.168.3.55:8240/login   # iam-web 前端
  internal_token: ""                           # 走环境变量

# ---- 日志 ----
log:
  level: info
```

### camera.yaml（Camera 服务——引用 iam）

```yaml
# ============================================================
# ppbchat-camera 相机 AI 服务配置
# 描述：AI 图像分析/配额/用户同意
# ============================================================

server:
  grpc_port: 9106
  http_port: 9116

database:
  mysql:
    host: 192.168.3.55
    port: 3306
    database: ppb_camera
    dsn: ""

grpc_dependencies:
  iam_service:
    address: 192.168.3.55:9107
    purpose: JWT 验证/用户身份

log:
  level: info
```

### gateway.yaml（网关——引用所有服务）

```yaml
# ============================================================
# ppbchat-gateway 统一网关配置
# 描述：透明 HTTP 代理 + 路由分派 + WebSocket
# ============================================================

server:
  listen: 0.0.0.0:8080
  websocket_path: /ws

log:
  level: info

# ---- 上游服务（转发目标）----
upstreams:
  im_service:
    name: ppbchat-im
    grpc_address: 192.168.3.55:9102
    http_address: 192.168.3.55:9112
    timeout_ms: 3000
  file_service:
    name: ppbchat-file
    http_address: 192.168.3.55:9114
    timeout_ms: 30000
  iam_service:
    name: ppbchat-iam
    grpc_address: 192.168.3.55:9107
    http_address: 192.168.3.55:9117
    timeout_ms: 3000
  camera_service:
    name: ppbchat-camera
    http_address: 192.168.3.55:9116
    timeout_ms: 3000
```

---

## 实施说明

| 步骤 | 内容 |
|---|---|
| 1 | 按上述模板重写 `deploy/config/*.yaml` |
| 2 | 各服务 Go 结构体的 yaml 标签对齐新键名 |
| 3 | `start-all.sh` 环境变量导出不变 |
| 4 | 旧配置可保留一份 `.legacy.bak` 供回退 |

**新键名 vs 旧键名对照**（以 file 为例）：

| 旧（扁平） | 新（分层） |
|---|---|
| `port: 9104` | `server.grpc_port: 9104` |
| `health_port: 9114` | `server.http_port: 9114` |
| `dsn: ""` | `database.mysql.dsn: ""` |
| `im_addr: ...` | `grpc_dependencies.im_service.address: ...` |
| `iam_addr: ...` | `grpc_dependencies.iam_service.address: ...` |
| `log_level: info` | `log.level: info` |
