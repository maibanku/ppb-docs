# 管理端插件修正任务书：列表的操作列不要换行

> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md) 的第 1 节（怎么配合、上下文怎么省）和第 5 节（报告格式）。环境里 Node 的部分照 [WS5 第二轮任务书](2026-11-25-ws5-round2.md) 的写法。

## 身份

- 工作流：WS6 管理端插件 mail-manage-web 的收尾修正（前面两轮已经做完：工程和 13 个页面、选人框、带凭据的导出）。
- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws6-fix`（worktree），分支 `fix/ws6-actions-column`（从 `main` 的 d25de8a 拉出，插件在它下面的 `mail-manage-web/`）。
- 只改 `mail-manage-web/` 下的东西。底座 `ppb-base/base-manage-web` 是别人的代码，只读。不改 `ppb-docs`，不推送，不合并。开发端口 8274（`8270` 被别的东西占了）。开发服务器、假后端、浏览器用完都关掉。

## 问题

第二轮的 agent 在真实的浏览器里（无头 Chrome，对着一个假后端）发现、没来得及修的问题，写在 `mail-manage-web/README.md` 的「已知缺口」里：

> 列表的操作列在真实浏览器里会换行：底座 `ProTable` 用 `#actions` 插槽时，操作列的最小宽度固定 150 像素；行操作有四到六个按钮的页面（域名、邮箱等）会折成两三行，并压住左边一列（固定列在玻璃主题下是透明的）。jsdom 里看不出来。

底座的实现（只读，`/Users/pipi-ban/Desktop/code/vscode/ppb-base/base-manage-web/src/components/ProTable.vue` 第 678 行起）：操作列的 `min-width` 是 `Math.min(320, Math.max(150, visibleActions.length * 80))`，而 `visibleActions` 来自 `actions` 属性；页面只用了 `#actions`（或 `#row-actions`）插槽、没传 `actions` 属性的时候，长度是 0，列宽就落到 150 像素。用这个插槽的页面在插件里有：`DomainsView`、`AccountsView`、`AliasesView`、`ForwardsView`、`BlocklistView`、`OutboundPolicyView`、`DeliveryLogsView`、`FilterLogsView`（自己再全量搜一遍，别漏）。

## 要做的

1. **先在真实的浏览器里复现并留一张截图**。上一轮留下的工具可能还在：`/tmp/ws6/mock-server.mjs`（假的后端）、`/tmp/ws6/browser-check.mjs`（无头 Chrome 的检查脚本）、`/tmp/ws6/shots/`。能用就复用，不能用就照着重写一个最小的（起插件的开发服务器，把代理指到假后端，用无头 Chrome 打开几个列表页，量操作列里按钮的行数和有没有压住左边的列）。
2. **修**。方向自己定，两个约束：不动底座；修完之后在真实的浏览器里，四到六个行操作的页面，操作列里的按钮不换行、不压住左边的列，1440 宽的窗口下整个表格还能正常看。可以考虑的：
   - 给这些页面传 `actions` 属性（底座按它的条数算列宽），插槽继续用来自定义按钮的渲染；
   - 按钮多的页面把次要的收进一个「更多」下拉；
   - 两者结合。
   不管选哪种，权限的显示逻辑不能变（没有对应权限的按钮不显示），每页现有的页面测试要继续通过。
3. **加一条能在 jsdom 里失败的测试**，守住「用了操作列插槽的页面都给了底座算列宽需要的信息」（或者你选的做法对应的那个不变量），免得以后又退回去。
4. 在真实的浏览器里逐页看一遍有操作列的页面（至少：域名、邮箱、别名、黑白名单、出站限额、投递日志），确认都好了；留两张修前修后的截图到 `mail-manage-web/docs/`（或 README 里说的位置）。
5. `README.md` 里「已知缺口」的那一条删掉或改成修好的说明；和你选的做法有关的约定写进去。

## 完成标准

- `npm run typecheck`、`npm test`、`npm run build`、`npm run build:lib` 在 Node 24 下通过（Node 在 `/Users/pipi-ban/.nvm/versions/node/v24.21.0/bin`）。
- 真实浏览器里操作列不换行、不压列（截图为证）。
- 工作区干净，提交都在 `fix/ws6-actions-column` 上。不要用 Agent 工具再派子 agent。

## 报告

按共用说明第 5 节：提交列表、四条命令的结果、你选的做法和原因、真实浏览器里逐页的结论、没做的。
