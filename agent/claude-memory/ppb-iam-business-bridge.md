# ppb IAM 业务桥（lane D，2026-10-28）

统一 Admin+IAM 任务后端桥实现要点（详见 ppb-base/server-gateway/docs/iam-business-bridge.md）：

- 通道：/iam/api/v1/business/manage/** 在 /iam/* 直通 handler 内分派（gin 通配已占路由树，不能另注册）；重写为 /api/v1/manage/** 复用同一 Registry（LookupInvocation 导出）。
- 网关每请求 GET IAM httpAddress /iam/api/v1/manage/context?surface_key=platform，仅转发 ppb_iam_session Cookie（Path=/），不跟随重定向，401/403 IAM 码透传，其余 SYSTEM-502 fail-closed。
- 断言：server-pkg/authzport/iamassert.go——HMAC-SHA256(PPB_INTERNAL_RPC_TOKEN)，绑定 gRPC fullMethod+actor+app_perms+iat/exp（TTL 30s、上界 2min、skew 1min）；网关 dial 链 IAMAssertionClientInterceptor 签发，metadata x-ppb-iam-assertion。
- 下游：authzport.UnaryServerInterceptor 内建断言验证（file/im 零装配改动）；server-user 挂 IAMAssertionServerInterceptor，requirePerm(ctx,...) 断言优先、actor 不一致即拒、无 legacy 回退。
- Requirement.IAMAppKey 覆盖：file 服务全量 chat→file（IAM file 独立应用授权）；网关桥同口径重映射 /manage/file/*。
- 治理红线：deny 段 login/admins/roles/menus/me/my-perms；super_gov 拒绝；is_super 不通配业务权限；不做账号自动关联。
- CSRF：Origin 须与 Host 一致（Vite 代理须保留 Host/changeOrigin=false）；Sec-Fetch-Site 仅 same-origin/same-site（none 仅 GET/HEAD）；无两头=非浏览器放行。
- 测试基线坑：server-user/internal/repo TestMenuSeedPolicy 因 deploy/sql/seed_menus.sql（09:47 改，23→21 菜单）失败为存量问题，非桥引入。
