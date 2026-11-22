# ppbChat 本地域名与 Nginx 反代配置

> 日期：2026-11-22 · 机器：192.168.3.55（macOS）· 目标：`*.pipiban.top` 域名 → 本机服务端口

---

## 一、完整域名→端口映射总表

### HTTP 服务（需 nginx 反代）

| 域名 | 端口 | 服务 | 说明 |
|---|---|---|---|
| `gateway.pipiban.top` | **8080** | 统一网关 | API 唯一入口（IM/File/Camera/IAM 透传 + WebSocket） |
| `iam.pipiban.top` | **9117** | IAM 认证 | OIDC Provider + 会话端点 |
| `iam-portal.pipiban.top` | **8240** | IAM 登录页 | 登录/注册前端（vite dev） |
| `manage.pipiban.top` | **8210** | 统一管理门户 | base-manage-web（挂载全部管理插件） |
| `manage-chat.pipiban.top` | 8220 | IM 管理 | 聊天管理插件（独立调试用） |
| `manage-camera.pipiban.top` | 8230 | 相机管理 | 相机管理插件 |
| `manage-iam.pipiban.top` | 8241 | IAM 管理 | IAM 管理插件 |
| `manage-file.pipiban.top` | 8260 | 文件管理 | 文件管理插件 |
| `minio.pipiban.top` | **9000** | MinIO API | 对象存储 |
| `minio-ui.pipiban.top` | **9001** | MinIO Console | 存储管理界面 |
| `livekit.pipiban.top` | **7880** | LiveKit | WebRTC 音视频信令 |

### TCP 直连（仅 hosts 条目，不走 nginx）

| 域名 | 端口 | 服务 | 说明 |
|---|---|---|---|
| `mysql.pipiban.top` | **3306** | MySQL 8.0 | 数据库 |
| `redis.pipiban.top` | **6379** | Redis 7 | 缓存/消息 |
| `im-grpc.pipiban.top` | 9102 | IM gRPC | 服务间内部 RPC |
| `file-grpc.pipiban.top` | 9104 | File gRPC | 服务间内部 RPC |
| `camera-grpc.pipiban.top` | 9106 | Camera gRPC | 服务间内部 RPC |
| `iam-grpc.pipiban.top` | 9107 | IAM gRPC | 服务间内部 RPC |

### Dev 专用（不配域名，仅本地开发时用）

| 端口 | 服务 | 说明 |
|---|---|---|
| 1420 | 桌面端 vite | `tauri dev` 时自动启动 |
| 8081 | Expo Metro | 手机端开发时自动启动 |

### 备用/未运行

| 端口 | 服务 | 说明 |
|---|---|---|
| 5672 | RabbitMQ | 事件队列（未部署，按需启用） |

---

## 二、Nginx 配置（Docker 容器）

### docker-compose.yml 追加（infra/docker-compose.yml）

```yaml
  nginx:
    image: nginx:1.27-alpine
    container_name: ppb-nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### nginx.conf

```nginx
worker_processes auto;
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # 通用代理头（后端取真实 IP）
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket 升级（网关需要）
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    # ---- 统一网关（API 入口）----
    server {
        listen 80;
        server_name gateway.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:8080;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_read_timeout 300s;
            client_max_body_size 110m;
        }
    }

    # ---- IAM 认证（OIDC Provider）----
    server {
        listen 80;
        server_name iam.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:9117;
        }
    }

    # ---- IAM 登录页前端 ----
    server {
        listen 80;
        server_name iam-portal.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:8240;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }

    # ---- 统一管理门户 ----
    server {
        listen 80;
        server_name manage.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:8210;
        }
    }

    # ---- 管理插件（独立调试用）----
    server {
        listen 80;
        server_name manage-chat.pipiban.top;
        location / { proxy_pass http://host.docker.internal:8220; }
    }
    server {
        listen 80;
        server_name manage-camera.pipiban.top;
        location / { proxy_pass http://host.docker.internal:8230; }
    }
    server {
        listen 80;
        server_name manage-iam.pipiban.top;
        location / { proxy_pass http://host.docker.internal:8241; }
    }
    server {
        listen 80;
        server_name manage-file.pipiban.top;
        location / { proxy_pass http://host.docker.internal:8260; }
    }

    # ---- MinIO ----
    server {
        listen 80;
        server_name minio.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:9000;
            client_max_body_size 100m;
        }
    }
    server {
        listen 80;
        server_name minio-ui.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:9001;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }

    # ---- LiveKit ----
    server {
        listen 80;
        server_name livekit.pipiban.top;
        location / {
            proxy_pass http://host.docker.internal:7880;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
```

---

## 三、/etc/hosts 条目

```bash
# ppbChat 本地域名（HTTP → nginx:80 / TCP → 直连端口）
127.0.0.1    gateway.pipiban.top
127.0.0.1    iam.pipiban.top
127.0.0.1    iam-portal.pipiban.top
127.0.0.1    manage.pipiban.top
127.0.0.1    manage-chat.pipiban.top
127.0.0.1    manage-camera.pipiban.top
127.0.0.1    manage-iam.pipiban.top
127.0.0.1    manage-file.pipiban.top
127.0.0.1    minio.pipiban.top
127.0.0.1    minio-ui.pipiban.top
127.0.0.1    livekit.pipiban.top
# TCP 直连（不走 nginx）
127.0.0.1    mysql.pipiban.top
127.0.0.1    redis.pipiban.top
127.0.0.1    im-grpc.pipiban.top
127.0.0.1    file-grpc.pipiban.top
127.0.0.1    camera-grpc.pipiban.top
127.0.0.1    iam-grpc.pipiban.top
```

---

## 四、启动命令

```bash
# 1. 写入 hosts（需 sudo）
sudo tee -a /etc/hosts << 'EOF'
# ppbChat 本地域名
127.0.0.1    gateway.pipiban.top
127.0.0.1    iam.pipiban.top
127.0.0.1    iam-portal.pipiban.top
127.0.0.1    manage.pipiban.top
127.0.0.1    manage-chat.pipiban.top
127.0.0.1    manage-camera.pipiban.top
127.0.0.1    manage-iam.pipiban.top
127.0.0.1    manage-file.pipiban.top
127.0.0.1    minio.pipiban.top
127.0.0.1    minio-ui.pipiban.top
127.0.0.1    livekit.pipiban.top
127.0.0.1    mysql.pipiban.top
127.0.0.1    redis.pipiban.top
127.0.0.1    im-grpc.pipiban.top
127.0.0.1    file-grpc.pipiban.top
127.0.0.1    camera-grpc.pipiban.top
127.0.0.1    iam-grpc.pipiban.top
EOF

# 2. 创建 nginx 配置目录并启动
cd infra
mkdir -p nginx
# （将上方 nginx.conf 内容保存到 nginx/nginx.conf）
docker compose up -d nginx

# 3. 验证
curl http://gateway.pipiban.top/ping
curl http://iam.pipiban.top/ping
curl http://manage.pipiban.top/
```

---

## 五、域名使用示例

| 场景 | 之前 | 之后 |
|---|---|---|
| 桌面端服务器地址 | `http://192.168.3.55:8080` | `http://gateway.pipiban.top` |
| IAM OIDC issuer | `http://192.168.3.55:8080/iam` | `http://gateway.pipiban.top/iam` |
| 管理后台 | `http://192.168.3.55:8210` | `http://manage.pipiban.top` |
| MinIO 控制台 | `http://192.168.3.55:9001` | `http://minio-ui.pipiban.top` |
| MySQL 连接 | `192.168.3.55:3306` | `mysql.pipiban.top:3306` |
