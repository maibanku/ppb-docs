# 内部服务接口怎么写、怎么定义（含完整范例）

> 日期：2026-11-23 · 适用：服务间 RPC（内部东西向流量）
> 关联：`grpc-to-http-howto.md`（外部接口篇）、`kitex-placement-map.md`
> 范例：RefAccess（file→im 跨服务裁决）——最小且完整的三方闭环

## 一、定义在哪：contracts proto 是唯一事实源

内部接口 = `contracts-*/proto/*.proto` 的 `service` + `message`。归属规则：
**契约放「域权威方」的 contracts 仓，实现与调用各自所在服务仓**（RefAccess
契约在 contracts-file、服务端在 service-im、调用方 service-file——三方三仓，
靠契约仓解耦）。

## 二、定义约定（配真实片段）

```proto
// 头注释 = 契约正文（接入规则/fail-closed/扩展方式，评审必读）
// ppbChat 引用访问裁决统一回调契约（v1）：file 按 refType 路由到引用方服务
// 实现的 CheckRefAccess——新调用方接入 = 分配 refType + 配置回调地址 +
// 实现本契约，file 侧代码零改动。im（refType=1）/ mail（refType=2）。
// fail-closed：实现方内部错误一律 allowed=false；refType 不归属自身域一律 allowed=false。
syntax = "proto3";
package refaccess;
import "common.proto";
option go_package = "github.com/maibanku/ppb-file/contracts-file/gen/go/refaccess";

service RefAccessService {
  rpc CheckRefAccess(CheckRefAccessReq) returns (CheckRefAccessResp);
}
message CheckRefAccessReq {
  int32 refType = 1;   // 引用类型（1=im 2=mail）
  uint64 memberId = 2; // 待裁决成员主键 id
  uint64 refId = 3;    // 引用方主键 id
}
message CheckRefAccessResp {
  common.BaseResp base = 1;
  bool allowed = 2;
}
```

约定清单：

| 约定 | 内容 |
|---|---|
| **信封** | 每个 Resp 首字段 `common.BaseResp base = 1`；**业务错误只走信封（BizCode/Message/HttpStatus），RPC error 恒 nil**；传输层错误留给中间件/熔断语义 |
| **字段域（内外有别）** | 内部 RPC 用**数值主键**（uint64 id-only 终态）；对外 HTTP 才是十进制字符串——转换只发生在契约面 |
| **时间** | RFC3339 字符串（proto 头注释约定） |
| **头注释即契约** | 语义/接入规则/扩展点/fail-closed 口径写在 proto 头部，编号引用（如 camera.proto「约定 #5」） |
| **fail-closed** | 裁决/查询类接口：内部错误等价于拒绝，不半开 |
| **扩展点显式化** | 枚举 refType 这类「新参与方零改动接入」的通道在契约层声明 |
| **信任模型** | 调用方必带 `x-ppb-internal-token`（共享凭据）；管理类方法另带 IAM 断言（按 fullMethod 绑定 + TTL），服务端中间件链 fail-closed 校验 |

## 三、生成链（定义完成后）

1. contracts 根模块 `buf generate` → `gen/go/<pkg>`（proto.Message 类型 + gRPC
   客户端桩——HTTP 面与 grpc-go 回退路径共用）
2. 契约仓旁挂模块 `contracts-X/kitexstubs` 生成 kitex 服务组——**单一生成点**，
   与 `gen/go` 同仓同节奏发 tag；服务仓按需 `require`，不再各自持有 kitex_gen
   拷贝（2026-11-24 落位地图方案 B 起，原「自足式 kitex_gen」已取代）
3. kitexstubs 一律用别名层（`type X = contracts.X`）共享同一 Go 类型——handler /
   客户端签名与 gRPC 版同形，业务层零改动

## 四、实现方怎么写（service-im）

`internal/transport/refaccess/ref_access_kitex.go`：

```go
// CheckRefAccess 引用裁决回调：不归属自身域的 refType 返回 allowed=false。
func (h *RefAccessHandler) CheckRefAccess(ctx context.Context, req *refaccess.CheckRefAccessReq) (*refaccess.CheckRefAccessResp, error) {
    // fail-closed 判定 → 领域服务 → 信封返回（error 恒 nil）
}
```

编译期断言 `var _ refaccess.RefAccessService = (*RefAccessHandler)(nil)`
锁接口完整实现；中间件链（Recovery→InternalAuth→[断言/权限]→RequestID）
在 boot_wire 装配，实现方零鉴权代码。

## 五、调用方怎么写（service-file，三层）

1. **业务层窄口**（`internal/file/service/file_ports.go`）——纯 Go 签名，
   业务代码**不 import proto**：

   ```go
   type RefAccessChecker interface {
       CheckRefAccess(ctx context.Context, refType int8, memberID, refID uint64) (bool, error)
   }
   ```

2. **客户端薄适配**（`internal/client/grpc/refaccess/access_grpc_client.go`）——
   构造 proto req → 调用 → 解包信封：

   ```go
   func (c *GRPCRefAccessChecker) CheckRefAccess(ctx context.Context, refType int8, memberID, refID uint64) (bool, error) {
       resp, err := c.cli.CheckRefAccess(ctx, &refaccess.CheckRefAccessReq{...})
       ...
   }
   ```

3. **装配 + 灰度双路**（`cmd/file/im_outbound.go`）——`service_name` 非空走
   kitex client（etcd 发现 + 重试/熔断 + 出站中间件），空则 grpc-go 直连
   address（内部凭据自动注入）。业务层对传输不可见。

## 六、接口演进流程

proto 变更（加方法/加字段，禁止破坏性变更）→ contracts 仓 review + **根模块与
kitexstubs 成对发 tag** → 实现方升级（handler + 编译期断言自动点名缺失方法）
→ 调用方按需升级（窄口不变则零改动）。两模块须成对抬版：只升根模块、不升
kitexstubs 时，新方法不被 Kitex 服务组伺服且**编译期无感**——由接口级对等锁
`service-im/cmd/server/kitex_parity_test.go`（九组方法集 ↔ contracts 权威反射
对拍）兜住。拷贝级同步门禁（alias_sync / sync_test）已随拷贝件退役。

## 速查

| 物 | 位置 | 谁 |
|---|---|---|
| 接口定义 | contracts proto（头注释=契约正文） | 域权威方 |
| Go 类型 | contracts gen/go + `contracts-X/kitexstubs`（别名层，单一生成点） | 生成 |
| 实现 | transport *_kitex.go + 编译期断言 | 服务方 |
| 调用 | 窄口接口 → 薄适配 → 灰度装配 | 消费方 |
| 鉴权 | 中间件链（凭据/断言/权限表） | 装配层，双方零代码 |
