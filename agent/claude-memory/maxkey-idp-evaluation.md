---
name: maxkey-idp-evaluation
description: 2026-10-27 MaxKey 及 IdP 选型调研结论（面向 ppb 统一认证入口）
metadata:
  node_type: memory
  type: project
  originSessionId: 60254c68-00fb-4b08-b267-848f4f83d2fa
  modified: 2026-10-26T22:36:37.916Z
---

2026-10-27 对 MaxKey（dromara/MaxKey，v4.2.0 2026-10-21，Apache-2.0，bus factor=1：shimingxy >95% 提交）完成 8 路调研 + 对抗验证。

- **安全**：CVE-2026-69102（CVSS 9.8，硬编码 JWT 密钥 + `/sign/login/jwt/trust` 免密接管，≤4.1.11，4.1.12 修复，4.2.0 已含）；CVE-2025-6517（SSRF）。仅内网/VPN + 加固可接受。
- **OIDC 成色（源码实测）**：PKCE ✅（S256/plain，应用级开关）；discovery 有陷阱——不带 `client_id` 时 jwks_uri/issuer 为空，标准自动发现失败，须手工配端点；access_token 为不透明 UUID（走 introspect 或只验 id_token）；登出非 OIDC 规范（私有 logout-notify + `/force/logout`）；OAuth 底座是 EOL 的 Spring Security OAuth 2.x 整体 fork（#269 redirect_uri 绕过已修）。端点路径 main 线（/authz/oauth/v20/）与 4.1.X 文档（/maxkey/oauth2.0/）不一致，版本相关。
- **SCIM 仅入方向、草案版**：开源版无出方向供给，「离职一次禁用全线失效」宣传不实。
- **社区/商业**：文档教程仍停 3.5.0 时代、协议文档挂 star 授权墙；企业版 ¥4.5W 起 / IDaaS ¥5.9W 起、功能边界不公开；社区版有永久免费商用承诺。
- **Go 团队适配结论**：横评推荐 **Casdoor > ZITADEL（AGPL 政策关）> Keycloak > MaxKey**；若用 MaxKey 只能 BFF 模式（后端 confidential client）。
- **方法论教训**：社区口碑调研路产出了 issue 幻觉数据（#1401/#1402 不存在，仓库编号至今仅 ~#277），被验证器证伪作废——引用 MaxKey 的 issue/版本类数据必须逐条 API 核实；jsdelivr 读 main 分支文件有陈旧缓存（曾误报 Spring Boot 3.5.9）。

关联 [[ppb-unified-usercenter-audit]]。
