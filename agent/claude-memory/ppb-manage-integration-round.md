# ppb manage 集成轮收口（2026-10-29，Claude 独立执行）

ppb-base 9d0c00e→c62bd6c（5 实质提交，commit_unit sequence 33-37，未 push）。收口报告：
`Documents/Codex/2026-10-28/new-chat-2/outputs/Claude独立执行收口报告.md`；验收留痕
`…/work/claude-control/autonomous-next/c_gateway/acceptance-runs/20261029-102123`（68/68）。

## 后续轮：权限隔离修复（10-30）+ catalog 合并解冻轮（10-31）
- 10-30 三提交 2f199a4/3342531/77115d0 修完 Codex 验收五缺陷（SeedPlatformWithIsolation
  权威入口/关联弹窗/条件取数/写口重查/0010 事务+0011）——用户贴的"用量上限失败"现场
  之后实际已跑完，勿重做。冻结的 catalog.go/registry.go/0005 dirty 已被 d47b960 收编入库。
- 10-31 解冻轮（7aef40c+4ac16e9）：两层 ext（governance/perm_isolation）并回 iamDomain()
  本体，CatalogVersion 2026.10.31-1，ext 文件删除，0005 镜像重生成，0008 吸收删除，
  复审补 0012（旧入口隐藏 UPDATE 载体）。**Catalog() 现为唯一事实源**；Codex 五项升级
  回归旧库形态=priorGovernanceCatalog 从 Catalog() 剥离隔离增量构造；新绊线在
  catalog_merge_test.go。独立复审 Ready: Yes。
- **2026-10-31 已 push**：7aef40c/4ac16e9/5737f82 已推 origin/main（1913e2b..5737f82，
  用户显式授权，历轮「未 push」口径自此作废）。
- 仍未做（需用户授权）：真实 MySQL 执行 0009-0012+故障注入；浏览器登录态验收。
- → **两项均已于 10-31 补齐**：①本地 ppb-mysql 演练库全场景+故障注入+真库
  0012+seed（终态零残留/旧入口隐藏/版本 2026.10.31-1）；真实执行暴露 SQL 轨道
  三缺陷（INSERT 缺时间列 ERROR 1364 / ON DUPLICATE JOIN 二义 1052 / biz_key
  超宽 1406——mperm 键去 <app>. 前缀）已修（5737f82）。②playwright 浏览器
  验收 13/13（A 导航隐藏/B 不发 GET menus/C 不发 GET admins/D 关联弹窗闭环/
  E 撤权终裁）——**须走 platform 宿主 :8250**（iam-manage-web 独立宿主 8241
  vite '/iam' 代理前缀与 base /iam/ 冲突，SPA 不可达）；夹具=直插 dev 库
  （绕真 SMTP），用毕软删。目录节点挂映射会令子树角色继承码（dev 库曾污染，
  已清空）。浏览器/MySQL 验收细节见复验报告 §八/§九。

## 关键事实
- USER-9501 已消除：im dial 链补 IAMAssertionClientInterceptor；七方法走
  rpcclient.IAMAccountClient（server-im/internal/rpcclient/iam_provision.go）。
- iamx 桥接面：idl/iamx.proto `IamAccountBridge`（biz_key↔数值 id、by-email，internalauth
  数据面无写路径）。**存在与并行会话未提交 ResolveUser 的功能重叠，待其提交后去重合并。**
- email-log 承接：iam_email_send_log 表 + LogSendCodeSender 装饰投递器（码位掩码）+
  server-iam ListEmailSendLog。
- 邀请成员面：gateway /user/invitations/{send-code,accept} 已切指 UserOrg；accept 成功
  gateway 直签 24h member token（proxy/member_invite_mint.go，独立于并行会话 token_mint.go）。
- harness：`tools/manage-acceptance-next/run_acceptance.py`（68 case；--expect-invitations impl；
  从 repo 根跑，别让 cwd 被 hook 重置）；发布候选 c62bd6c 已 preflight PASS、未部署。

## 并行会话冻结协议（本轮核心经验）
用户称"进程已全部退出"但 PID 19492 全程活跃。处置：diff 定位其编辑集（member-login 集群 +
todo 半成品）→ 全部冻结（不提交/不修改/不还原）→ 我的改动走不相交文件 → proto 新增走**新文件
idl/iamx.proto**（buf generate --path 仅产新文件，避免 entangle 其未提交 grpc_gen）→
验收一律 git archive HEAD 快照构建（天然隔离 dirty）。todo 半成品会使 server-im 工作树
go build ./... 失败——用 HEAD 快照/定向包测试绕过，勿替它修。

## 待并轨（下次会话先查）
1. 并行会话 member-login 两步链提交后：ResolveUser×iamx 去重、/user/login 503 缺口消除、
   其 token_mint.go Minter×我的 member_invite_mint.go 收敛。
2. deploy/bin 切换人工放行清单（release-candidate/config-diff.txt）。
