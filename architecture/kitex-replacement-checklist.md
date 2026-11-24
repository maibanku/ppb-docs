# ppbChat 后端 Kitex 替换检查手册（逐服务执行版）

> 日期：2026-11-23 · 适用：Kitex 迁移 P1-P4 落地后的全量替换核验
> 用法：对每个后端按 §1→§2→§3 顺序逐项执行；任一项 FAIL 即为遗漏，直接修复后重跑该项。
> 前置环境（每条命令前设置）：
>
> ```bash
> export PATH=$HOME/sdk/go1.26.0/bin:$PATH GOPROXY=https://goproxy.cn,direct GOPRIVATE=github.com/maibanku/* GOFLAGS=-mod=mod
> ```
>
> 检查对象（RPC 后端四件）：im（ppb-chat/service-im）、iam（ppb-iam/service-iam）、
> file（ppb-file/service-file）、camera（ppb-camera/service-camera）。
> 网关（ppb-gateway）为 HTTP 反代，按设计不迁移，仅确认无 RPC 服务端代码。
> 出站 grpc-go 客户端（internal/client/grpc/*）属 Phase C 范围，**不算残留**；
> contracts 仓的 gen/go gRPC codegen 是回环/出站客户端的类型源，**保留**。
>
> **2026-11-24 修订（落位地图方案 B）**：im/iam/file 的 kitex 服务组已收口到
> `contracts-{im,iam,file}/kitexstubs` 旁挂模块，三仓服务目录下**不再有
> `kitex_gen/`**（kitex 服务组不在 `<SVC>` 内，§1.1/1.2/1.5 的排除模式不受影响）；
> camera 自 serving 仍在 `service-camera/kitex_gen/camera`。§1.7、§1.8 已按此修订。
> §2 预期包数相应 −1（kitex_gen 测试包随拷贝退役）：im 24 / iam 19 / file 10 /
> camera 14；其中 iam/file/camera 各有 1 条 deploy 配置兼容门禁的预存红
> （跨仓时序倒置，非 Kitex 遗留，见落位地图 §六）。

## §1 静态检查（每服务同口径，任一命中即 FAIL）

在 `/Users/pipi-ban/Desktop/code/vscode` 下执行（`<SVC>` 为服务目录）：

### 1.1 无真实 gRPC 服务端代码

```bash
grep -rn "grpc\.NewServer\|reflection\.Register" --include="*.go" <SVC> \
  | grep -vE "^\S+:\s*//|_test\.go|kitex_gen|gen/go"
# 预期：无输出（注释/测试/生成代码除外）
```

### 1.2 无旧式 Register*Server 装配调用

```bash
grep -rn "Register.*Server(s,\|Register.*Server(gs,\|Register.*Server(svr," --include="*.go" <SVC> \
  | grep -vE "_test\.go|kitex_gen|gen/go"
# 预期：无输出
```

### 1.3 处理器已切 Kitex（无残留 *_grpc.go 传输层文件）

```bash
find <SVC>/internal/transport -name "*_grpc.go" 2>/dev/null
# 预期：无输出（internal/client/grpc/ 下的出站客户端适配器除外）
```

### 1.4 装配面用 Kitex（boot 含 kitexserver + kitexstarter）

```bash
grep -l "kitexserver.NewServer" <SVC>/cmd/*/*/boot_wire.go
grep -l "kitexstarter.Wrap" <SVC>/cmd/*/*/boot_wire.go
# 预期：两者都命中；且同文件 grep -c "grpcstarter" = 0
```

### 1.5 无 Unimplemented*Server 内嵌（传输层）

```bash
grep -rn "Unimplemented.*Server\`" --include="*.go" <SVC> | grep -vE "_test\.go|kitex_gen|gen/go"
# 预期：无输出
```

### 1.6 服务根无 kitex 脚手架杂物

```bash
ls <SVC> | grep -E "^(handler\.go|build\.sh|kitex_info\.yaml|main\.go|script)$"
# 预期：无输出
```

### 1.7 kitex 服务组在位（kitexstubs require）+ registry 配置在位

```bash
grep -n "kitexstubs" <SVC>/go.mod
find <SVC> -type d -name kitex_gen
grep -rn "registry" <SVC>/config.yaml <SVC>/internal/config/*.yaml 2>/dev/null | grep -c etcd
# 预期：kitexstubs require ≥1 处；kitex_gen 目录仅 camera 命中（自 serving 的 camera/ 服务组）；
#       etcd 配置 ≥1 处
```

### 1.8 contracts 仓纯净（无 kitex 脚手架）

```bash
ls ppb-chat/contracts-im ppb-file/contracts-file ppb-iam/contracts-iam ppb-camera/contracts-camera \
  | grep -iE "kitex|handler\.go|build\.sh|script" | grep -vx "kitexstubs"
# 预期：无输出（kitexstubs/ 旁挂模块是方案 B 的单一生成点，属预期；
#       根模块其余位置仍不得沾 kitex 脚手架——kitex 只进旁挂子模块）
```

## §2 构建与测试（每服务）

```bash
cd <SVC>
GOWORK=off go build ./... && GOWORK=off go vet ./...
GOWORK=off go test ./...          # 预期 0 FAIL；计时抖动用例先原样重跑一次再判
```

## §3 运行时检查（每服务，备用端口 291xx 互不干扰）

```bash
# 3.1 起服（备用口配置可复用 /tmp/kitex-verify/configs 模板；端口 910x→2910x、911x→2911x 重映射，
#      grpc_dependencies 同步重映射形成闭环；iam 特例：用服务自身 config.yaml 做基底——deploy 版
#      schema 超前于严格解析会拒起）
# 3.2 etcd 注册键（etcd 常驻 127.0.0.1:2379）：
ETCDCTL_API=3 /tmp/etcd-extract/etcd-v3.5.12-darwin-arm64/etcdctl \
  --endpoints=127.0.0.1:2379 get --prefix "kitex/registry-etcd/<服务名>" --keys-only
# 预期：kitex/registry-etcd/ppbchat-<svc>/<lan-ip>:<rpc-port>
# 3.3 健康口：curl http://127.0.0.1:<http-port>/ping（im 为 /healthz）→ 200 自描述 JSON
# 3.4 HTTP 面→回环→Kitex 全链路：camera=GET /api/v1/camera/templates（匿名白名单）；
#     其余服务可用管理面无凭据负例（401/403 而非 503）作面级探针
# 3.5 停机反注册：kill 进程后 etcd 键消失
# 3.6 跨服务证据（可选，针对有 IAM 依赖的服务）：lsof -p <pid> | grep 9107 → ESTABLISHED
```

服务名/端口对照：`ppbchat-im`(29102/29112)、`ppbchat-file`(29104/29114)、
`ppbchat-camera`(29106/29116)、`ppbchat-iam`(29107/29117)。

## 已知遗漏登记（本次扫描发现，修复后勾销）

- [x] **im `cmd/smoke/main.go`**：stub user/file 依赖模拟服务仍为 `grpc.NewServer`（93/113 行）——
      四后端中仅存的真实 gRPC 服务端代码。**已修复（2026-11-23）**：两桩均转 Kitex server
      （user 桩经 im 别名层 orgcompatservice 直挂；file 桩新增 `kitex_gen/go/file` 别名层
      + 自 ppb-file 同版拷入的 fileservice 服务组，contracts Unimplemented 内嵌经别名
      结构兼容满足 Kitex 接口——编译期断言锁定）；smoke 客户端补内部凭据注入
      （internalauth.UnaryClientInterceptor）；前置成员种子 SQL 记入 smoke 文件头。
      修复后实跑 **ALL PASS**（grpc-go 客户端 × Kitex im 服务端 + Kitex 桩依赖 + 真库全链路）。

## 执行实录（2026-11-23 按本手册逐项执行）

| 检查 | im | iam | file | camera |
|---|---|---|---|---|
| §1.1-1.8 静态 | 修复后全过（smoke 桩见上） | 全过 | 全过 | 全过 |
| §2 build/vet/test | 24 包 ok/0 FAIL | 20 包 ok/0 FAIL | 11 包 ok/0 FAIL | 15 包 ok/0 FAIL |
| §3.2 etcd 注册键 | ✓ 29102 | ✓ 9107 | ✓ 29104 | ✓ 29106 |
| §3.3 健康口 | /healthz 200 | /ping 200 | /ping 200 | /ping 200 |
| §3.4 面级探针 | **smoke ALL PASS**（建群/发消息/幂等/已读/补拉/撤回十步全绿，含 Kitex 桩依赖+真库） | qatokens RPC 码文案精确（P2 验收） | manage 无凭据 401（非 503） | templates API 全链路 200 |
| §3.5 停机反注册 | ✓ | ✓ | ✓ | ✓ |
| §3.6 跨服务证据 | camera/im/file→IAM ESTABLISHED（lsof 连接层） | —（被依赖方） | ✓ | ✓ |

smoke 运行口径（im §3.4 复现命令）：

```bash
cd ppb-chat/service-im
env PPB_INTERNAL_RPC_TOKEN=<token> SMOKE_IM_ADDR=127.0.0.1:<im-rpc口> \
  SMOKE_FILE_ADDR=<im配置中file地址> SMOKE_USER_ADDR=127.0.0.1:39101 \
  GOWORK=off go run ./cmd/smoke/    # 预期 == 冒烟结果：ALL PASS ==
```
