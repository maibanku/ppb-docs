---
name: ppb-chat-org-domain
description: chat 组织域归属裁决——数据权威=server-im chat_* 表、管理页不可删、ppb_user 旧部门表是可清残留（2026-11-03 深查）
metadata:
  type: project
---

2026-11-03 深查裁决（用户问「组织管理下为何还有部门管理/企业设置，能否清」）：

- **重做只收编认证/授权，组织数据归属不变**：lane=user_retirement 把 /api/v1/manage/** 归口 UserOrg（server-im 组织子集）+ UserIam（server-iam 治理），见 server-gateway/proxy/registry_manage.go:3-6。IAM 只注册菜单目录（catalog.go:295-298 chat.departments、:309 chat.org-settings），无组织数据实现（iam-manage-web 13 视图无组织页）。
- **部门链路不可清**：ppb_im.chat_departments/chat_membership_departments 被桌面通讯录（contacts.go:76,119）、资料 DeptPath、成员 deptBizKey 必填、公告定向、导入按部门名全链消费。管理面与用户面同库。
- **企业设置=改组织名**：唯一字段 corpName 即 chat_workspaces.workspace_name（无 KV 表）；页面冗余可合并但字段/端点必须留（登录回执 corpName，member_auth.go:358）。catalog.go:309-318 该节点下挂 5 个隐藏操作码，砍菜单前需安置。
- **可清残留**：① ppb_user 三死物 department 表/user_department 表/department.seed.sql——仅 drill.go:506-526 迁移核查引用，「阶段5 迁移切换」欠账（chat_org_model.go:7）；② 前端 leader 死 UI（DepartmentsView.vue:233-238,523-548 有搜索/展示，后端 user_compat_org.go:133-136 显式拒绝，ADR-008#5 废弃 leader 列）。

关联 [[ppb-unified-usercenter-audit]] [[ppb-web-frontends]]。
