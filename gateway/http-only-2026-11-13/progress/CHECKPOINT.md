# 当前执行检查点

目标：server-gateway 最终只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。**P6 已完成**（858f6e5 已推送；活栈运行透明网关）。

基准：ppb-base/main@9989a6a → 当前 858f6e5。

## 全批次完成情况

- P0 基线/负控（docs）；P1 svcauth/authzauth 共享验证（0ae216a）；P2 IM 39 manage + 前转 + MQ 公告（f3c3524）；P3 IAM 登录编排/契约/业务桥（cc92503）；P4 file/camera 承接 + 桥全 owner（3f00420）；P5 实时面迁 IM + WS 透明升级（3f00420）；P6 透明网关唯一形态 + legacy 删除 + 依赖图干净（858f6e5）。
- ROUTE-STATUS 167/167 全量落位（163 service_http/special done + 4 P6 退役记录）。
- 透明网关依赖审计：`go list -deps ./server-gateway` 0 个业务禁项（此前 79 个 grpc 族）。
- 活体验证（透明网关）：/ping、登录编排全链（login/session/profile）、42 member 路由、manage 14/14、file/camera/桥全 owner 200、WS 101 升级、无凭据负控 401/404 拒绝。61 测试包全绿。
- 行为差异（已记录，均为拒绝语义等价）：未知路由 404（legacy 403）；方法不匹配 405（legacy 401）；camera JWT manage 直连 503（基线即如此——gRPC 面只收断言，桥为有效通道）。

## 当前批次：P7（部署/CI/全量验收收尾）

1. deploy/scripts/start-all.sh 对齐（透明网关启动带 -routes；camera 纳入启动面）。
2. .github/workflows/gateway-governance.yml 与 tools/ci.sh 更新（网关依赖审计门禁：禁项=非零退出；契约漂移检查 gen-routes 幂等）。
3. go.work 清理（无变更则不动）；go.mod tidy 各模块。
4. FINAL-ACCEPTANCE.md：逐项 A01-A17 证据；STATUS.json complete 判定。
5. 最终全量回归（restart-all + 全脚本 + WS 长连消息收发冒烟）。

## 纪律不变项

不 force push；密钥不进日志/提交；camera.pid 由本次会话管理（start-all 未纳管——P7 一并对齐）。
