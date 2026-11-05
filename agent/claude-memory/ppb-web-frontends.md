---
name: ppb-web-frontends
description: ppb 前端矩阵：底座(8210)/chat(8220)/camera(8230)/iam(8241)/platform(8250)/file(8260)，插件化单壳与命名空间路由
metadata:
  type: project
---

底座+插件跨仓 file: 挂载结构（2026-10-28 统一平台改造后）：
- 全部宿主经 base-manage-web `createAdminApp({plugins, surfaceKey, authMode:'iam', title})`（底座 2026-10-28 起默认 iam 模式；IAM 业务桥 /manage/* → /iam/api/v1/business/manage/*）
- 端口：base 8210(/base/) / chat 8220(/chat/) / camera 8230(/camera/) / iam 8241(/iam/) / **platform 8250(/platform/, chat+camera+file+iam 四插件单壳)** / **file 8260(/file/)**
- 路由命名空间契约：path `/chat/* /camera/* /file/* /iam/*`，路由名=IAM catalog menu_key 同形（chat.departments、camera.overview、file.overview、iam.users）；权限 meta.perm 必须对象形 `{app, perm}`（camera 曾传字符串永不拦截，已修）
- plugin 导出：chatManagePlugin / cameraManagePlugin / fileManagePlugin / iamManagePlugin（platform 经 vite 别名引兄弟仓源码：'chat-manage-web/plugin' 等；多源根 '@' importer-aware 解析 + dedupe 防双 vue）
- 跨包 typecheck 门面：各包 src/vendor/base-exports.ts（declare 型），tsconfig paths 把 'base-manage-web/exports' 与插件 specifier 映射到门面；vitest 也要 importer-aware '@' reroute（chat 踩过：base 新增 '@/core/runtime-config' 后 vitest 炸）
- chat 部门页权限码是 department.read（后端 PermDeptRead；seed_menus.sql 的 dept.read 是旧示例）
- file 域按钮码 provisional 映射：takedown/recycle/orphan → file.lifecycle.manage（catalog file 域 7 码无细分）
- 后端网关 8080，各服务健康口见 [[runbook-local-mac]]；IAM catalog route_key 尚未随前端命名空间化（lane A 待重播种子）。
