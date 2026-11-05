---
name: chat-desktop-rewrite-progress
description: chat-desktop(Tauri) 重写进度、E2E 要点与已知后端问题（2026-10-27）
metadata:
  node_type: memory
  type: project
  originSessionId: 2a7acd6e-b7f5-49d1-9446-f6b9aa8c9e62
  modified: 2026-11-04T23:46:11.945Z
---

chat-desktop 对 chat-client 的复写，2026-10-27 已完成：M1（补真实端到端）、M2 全量（Keychain 凭据/SQLite 按账号分库/断线排队补发/tryAutoLogin/pending-events 补拉）、M3 五刀（主动撤回+引用回复、会话内搜索+发送即留痕归并、附件全链、通讯录+群治理（懒建直聊 mem_ 中转键 ack 后重绑）、待办页）。共 9 提交（236a6b29…238c1350，未 push）。状态权威记录在 ppb-chat/docs/README.md §16。

E2E 要点：
- `cd chat-desktop/src-tauri && cargo test -- --ignored --test-threads=1`（tests/real_backend.rs，默认 ignore 不进门禁）
- 账号 test-b1-a|b@example.local，口令经 MySQL user_credentials 直写 bcrypt 注入（E2e-Pass-2026）；env 可覆盖 E2E_EMAIL_A 等
- 本机 ppb-base 后端是 **localhost MySQL/Redis/RabbitMQ 全依赖态**（user 进程连 3306/6379），deploy/data/ppb_user.db 不是服务真库；真库在 MySQL ppb_user
- 工具链：rustup stable 在 ~/.cargo/bin（PATH 必须显式 export；homebrew rust 1.68 撑不起 tauri2/keyring4）；rustfmt/clippy 需 rustup component add
- 测试基线：vitest 113 / cargo 75 / typecheck / build

已知 ppb-base bug（未修，别再踩）：permguard RBAC revision 非单调（日志 6↔7 抖动），`rev < g.version` 即 fail-closed 403（MANAGE-0004）→ manage 面 CreateMember/ResetPassword 间歇全拒；E2E 造号绕过方式=DB 直写口令。见 [[runbook-local-mac]]。

**2026-10-27 增量（晚）：** ①M3-6 游客态；logout 回游客态（dispose 仍回 login）。②**插件系统整体移除**（ppb-chat b4b06163 / ppb-base 8f8a6f2；ppb_plugin 库已 DROP）。③架构基线 chat-desktop/docs/ARCHITECTURE.md（六铁律+八扩展接缝）。⑤start-all PPB_SKIP_IAM=1 坑、file.yaml storage_backend 漂移坑。

**2026-11-03 R1 优化轮（agent team 五工作项，全部集成在分支未 push）：** ppb-base `feat/w2-start-all-stale`（W1 permguard revision 全局单调 + W2 start-all 旧二进制自动换新 + issuer 补丁，终验双超管 20× 零 403）；ppb-chat `feat/r1-ux`（W3 登录错误分支规范+12 用例、W5 UI token 主流化——圆角 10/14/20、气泡亮#a9e07c 暗#37583a/#2b313b、阴影加深，前后 20+20 张对比图在 chat-desktop/docs/ui-r1/；W4 mac-gui-drive 技能入库 .claude/skills/——click/getwin/ocr/px 工具+run-all 一键回归 7P/0F/2S）。设计文档 docs/superpowers/specs/2026-11-03-chat-optimization-r1-design.md。ppb_im 表判定：event_outbox/chat_sessions 是注册未接线死表；chat_workspaces=0 但 memberships=8 为种子脏状态（ListMyAnnouncements 悬空 workspace 雷）。UI 瑕疵下轮候选：1200×800 登录浮窗次级入口不渲染、登录错误双文案堆叠、AvatarMenu 偶发点击不开。Read 工具图像通道本会话失效——GUI 验证改用 Vision OCR（ocr.swift）+像素采样（px.swift）组合，已入技能库。

**2026-11-03 服务器地址文件配置化（TDD，未提交）：** 登录页服务器手输框移除（LoginOverlay v3）；唯一事实源 = app data 目录 `com.ppbchat.desktop/config.yaml`（dev/prod 分段 env 切换；缺文件自动生成缺省档；非法/缺 key/违反 SSRF 契约一律回退 `config::DEFAULT_GATEWAY`=`http://127.0.0.1:8080`）。链路：Rust `config::resolve_gateway`（serde_yaml 0.9 新依赖）→ `AppState.server_url` → `desktop_server_url` 命令 → 前端 `src/api/serverConfig.ts loadServerUrl()`（失败回退 CLIENT_CONFIG.gatewayUrl）；`desktop_ping` 改 ping `state.server_url`（返回值改 AppResult<bool>——Tauri 带 State 的 async 命令必须 Result）；commands.rs GATEWAY_BASE 常量已删；IAM issuer 派生 `${gateway}/iam` 跟随文件。基线：vitest 609 / cargo 111 全绿。已知既有抖动：friendCtxMenu.test.ts「切页 keepOpen」独立复跑约半数概率挂，与本改动无关。切 prod：改 yaml `env: prod` + prod.gateway 即可，无需重打包。

**2026-11-04 认证窗口+登录重构轮（feat/r1-ux 已提交 55818391，未 push）：** 提交后多轮微调（间距放宽/注册整行钮/窗口 400px 对齐门户卡）被用户手动回滚——桌面终态即 55818391：320×360 圆角小窗+QQ 风登录+无勾选默认记住密码/自动登录。 ①未登录/退出登录=无边框紧凑登录窗（终稿 **320×360**：头像 56、输入 36、卡片 gap 14/tab 负 margin -4/表单 gap 14/页脚 pad 8，min 300×340；tauri.conf 初始即小窗），登录成功才展开工作台（默认 1200×800；每轮退出记忆最近工作台几何+最大化/全屏态，`src/shell/loginWindow.ts` 串行队列+mode 缓存+macOS 全屏等真实 resize 再快照）；App 根层互斥挂载 LoginOverlay/ChatShell，退出即清旧账号 overlay 确认与图片灯箱单例（`clearSessionOverlays`/`closeImageViewer`）。②logout 语义改回 login 页（enterGuest→login，五处旧断言已更新）。③登录页 QQ 风重构：居中大头像（选中最近账号时显示其头像/姓名）+居中输入（无左侧字段名，aria-label 保留）+底线 Tab+账号历史下拉（AccountPicker，Esc/外点收起）+保存密码/自动登录勾选；保存密码只入系统钥匙串（login:v1:password: 命名空间，Rust 内解析，JS 永不见明文）；自动登录=按服务器设备级显式同意（默认关），仅启动 boot 闸门（desktop_try_autologin startup:true），显式退出不会自动登回；验证码 Tab 也有自动登录勾选。基线：vitest 686 / cargo 135 全绿。**坑：dev 未签名构建登录时 macOS 钥匙串授权弹窗会阻塞登录 IPC（token 保存为既有来源，本轮密码保存新增一处），用户须本人输登录密码授权；期间前端 20s 超时误报且原生会话可能已建立——生产签名版不受影响，改造建议=钥匙串写移出登录响应路径（未做）。** Read 工具图像通道仍不可用，GUI 验证用技能 ocr.swift。同轮追加（11-04 晚）：登录窗再压至 **320×450**（min 300×400，紧凑间距全套），忘记密码移到底部三链接行（注册·忘记密码·IAM）；**窗口真圆角**：tauri.conf `transparent:true`+`app.macOSPrivateApi:true`（macOS 透明窗必须私有能力），圆角 12px 画在 `.desktop-frame.login-shell`（overflow hidden；boot 闪屏同享），body.login-shell 透明——本机 beta 系统实测角点透出桌面+阴影生效（旧"beta 透明不绘制"结论只适用于整窗透明，微角透明没问题）。真机证据=超时误报那次登录原生侧已成功，密码/偏好落盘生效（账号回填+“已保存密码”占位）。friendCtxMenu.test.ts 间歇抖动经 stash 基线复验确系既有问题（基线 4 跑 1 挂）。

**2026-11-05 无勾选默认轮：** 去除保存密码/自动登录勾选，默认开启——密码登录后原生默认记密码；email/IAM/密码任何登录成功都武装下次启动自动登录（`Preferences::set_auto`，login_email/commit_iam 调 `arm_auto_login`）；显式退出仍不会自动登回（logout 抹指针+凭证天然保证）；UI 只剩装载职责（账号预填+已存密码占位/免密提交，`useLoginPreferences` 瘦身，`saveLoginPreferences` 前端已删）。布局坑：flex 卡片内 `margin-top:auto` 要加在**卡片直接子级**才生效；最终定稿=Tab 栏负 margin -6px 紧贴输入框、`.login-form{flex:1}` 撑满、submit 在表单内 `margin-top:auto` 贴底（空隙落在错误区与按钮之间）。另：dev 重编译后新二进制读钥匙串已存密码会被拒（ad-hoc 签名变），hasSavedPassword 退化为 false 是 dev 伪象，签名版无此问题。
