---
name: ppb-unified-usercenter-audit
description: ppb 统一用户中心审计——4 套身份体系指认与治理红线（2026-10-27 源码亲核重写）
metadata:
  node_type: memory
  type: project
  originSessionId: 60254c68-00fb-4b08-b267-848f4f83d2fa
  modified: 2026-10-26T22:36:32.628Z
---

2026-10-26 裁决：现状不满足统一用户中心。2026-10-27 源码亲核补写 4 套身份体系：

1. **chat 成员**：ppb-base/server-user member 面（`user`/`user_identities`/`user_credentials`/`auth_sessions`）；邮箱验证码+密码+OAuth（Google 实装，QQ/微信/Apple 仅占位）；JWT 24h、sid 绑会话可吊销
2. **manage 管理员**：`user_admin` 表；30min token 无会话不可吊销；三个 manage-web 共享 base 底座登录（file: 挂载）
3. **camera 主体**：`subjects` 表，匿名→短信/Apple 原地升级；server-camera auth 与 iOS AccountKit 均为骨架（M2）
4. **服务间 internalauth**：`PPB_INTERNAL_RPC_TOKEN` 共享静态 token（fail-closed，mTLS 为后续任务）

备选口径：老线 ppb-cloud-ui（RuoYi-Cloud-Plus）自成一套完整登录。

治理红线（plans/2026-10-26-cross-biz-authz.md:9,22）：**不是 SSO、不合并业务用户、不新建 camera 登录体系**；IdP 只能收编认证入口、保留三套账号主体。改造重心：网关 HS256 共享密钥 + typ 三型 token（member/manage/bind）+ 14 条硬编码白名单路由。

关联 [[maxkey-idp-evaluation]]。
