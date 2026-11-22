# ppbChat 登录认证优化需求文档（修订版 v2）

> 版本：v2.0 · 日期：2026-11-22 · 范围收缩：砍掉手机号/生物识别/扫码/魔法链接/企业 SSO
> 原则：基于现有 OIDC 链路 + 现有设置面板做增量，不新建页面不新加依赖

---

## 一、现有基础（不改动的部分）

这些**已经在生产运行**，本方案在此之上做接线：

| 组件 | 状态 | 说明 |
|---|---|---|
| OIDC 认证链 | ✅ 稳定运行 | 桌面环回 / 手机深链，唯一登录通道 |
| 桌面 Keychain（`authstore.rs`） | ✅ 已实现 | keyring v4，service=`ppbchat-desktop` |
| 手机 SecureStore（`secureStore.ts`） | ✅ 已实现 | expo-secure-store，版本化 JSON blob |
| IAM refresh 端点 | ✅ 已实现 | `POST /iam/api/v1/token`（grant_type=refresh_token） |
| 桌面 try_autologin | ✅ 已实现 | 读 Keychain → /me 验活 → 成功恢复 |
| 桌面设置面板 | ✅ 已实现 | 六个 tab（账户/外观/通知/快捷键/存储/关于） |
| IAM session 模型 | ✅ 已实现 | 含 device_label 字段 |

## 二、问题（只修一个断裂点）

```
OIDC 登录成功
  → IAM 返回 access_token + refresh_token
  → access_token 存入 Keychain/SecureStore ✅
  → refresh_token 丢弃 ❌  ← 唯一的断裂点
  ...
  1 小时后 access_token 过期
  → try_autologin 调 /me → 401
  → 没有刷新手段 → 降级登录页 → 用户重新走浏览器 OIDC
```

**修复这一个断裂点（存 refresh_token + 过期时刷新）= 自动登录从 0% 到 99%。**

---

## 三、必要工作（必须做，缺一不可）

### AUTH-01：Refresh Token 持久化

**做什么**：OIDC 兑换成功后，将 refresh_token 与 access_token 一并存入安全存储。

| 端 | 文件 | 具体改动 |
|---|---|---|
| 桌面 Rust | `iam_oidc.rs` | `exchange_code_for_tokens()` 返回值中 refresh_token 不丢弃 |
| 桌面 Rust | `session.rs` → `login_with_oidc` | 调 `secrets.save("refresh:{scope}:{memberId}", refresh_token)` |
| 手机端 | `iamChannelRn.ts` | OIDC 回调后提取 refresh_token 传入 `saveCredentials` |
| 手机端 | `secureStore.ts` | `StoredCredentials` 接口加 `refreshToken?: string` |

**不做什么**：
- 不改 `authstore.rs`（现有的 `save/load/delete` 方法已够用，只是多存一个键）
- 不改 IAM（refresh_token 生成和返回逻辑已有）
- 不改前端 UI（用户无感知）

### AUTH-02：静默 Token 刷新

**做什么**：`try_autologin` 遇到 401 时，用 refresh_token 向 IAM 换新 token。

| 端 | 文件 | 具体改动 |
|---|---|---|
| 桌面 Rust | `httpapi.rs` | 新增 `refresh_token()` 方法（POST /iam/api/v1/token） |
| 桌面 Rust | `session.rs` → `try_autologin_with_startup` | 401 分支：读 refresh → 调刷新 → 成功则重试 /me |
| 桌面 Rust | `login_preferences.rs` | OIDC 登录成功后置 `auto_login = true` |
| 手机端 | `rnApi/index.ts` | 同桌面的 401 → refresh → retry 逻辑 |

**降级链**（三层兜底）：
```
try_autologin
  → /me 200 → 直接恢复 ✅
  → /me 401 → 读 refresh_token
      → 刷新成功 → 新 token 写 Keychain → /me 200 → 恢复 ✅
      → 刷新失败（过期/撤销）→ 清凭证 → 登录页 ✅（现状行为）
```

### AUTH-03：等待页进度反馈

**做什么**：OIDC 等待期间桌面端显示步骤进度，替代当前的黑盒等待。

**改动仅两个文件**：

| 文件 | 改动 |
|---|---|
| `LoginOverlay.vue` | 等待卡片内容改为四步指示器（当前步高亮） |
| `auth/iamChannel.ts` | 监听 Rust emit 的 `iam://progress` 事件 |

**Rust 侧不需要新文件**——`iam.rs` 已有 `emit_callback_event`，加一个进度阶段参数即可。

四步状态：
```
① 已打开浏览器   → 用户看到浏览器弹出
② 等待授权       → 用户在浏览器输入凭据
③ 已收到回调     → 浏览器完成，环回监听器收到
④ 正在登录       → Rust 在兑换 token / 建立会话
```

---

## 四、值得做（第二优先，P0 稳定后）

### AUTH-04：已登录设备管理

**做什么**：在现有设置面板「账户」tab 内新增「已登录设备」区块。

**不新建页面**——挂在 `SettingsPanel.vue` 的 account tab 下。

| 层 | 文件 | 改动 |
|---|---|---|
| IAM | `iam_http.go` | 新增 `GET /iam/api/v1/sessions`（当前用户全部活跃会话列表） |
| IAM | `iam_http.go` | 新增 `DELETE /iam/api/v1/sessions/{id}`（踢出指定会话） |
| 桌面 Rust | `session.rs` | 新增 `list_sessions` / `revoke_session` 两个方法 |
| 桌面 Vue | `SettingsPanel.vue` | account tab 内加设备列表 + 踢出按钮 |
| 手机端 | `SettingsScreen.tsx` | 同桌面加设备列表 |

**展示信息**（利用 IAM 已有的 `device_label` 字段）：
```
┌─ 已登录设备 ──────────────────────┐
│ 🖥 Mac Desktop · 当前设备         │
│    2026-11-22 15:30 · Chrome     │
│                                   │
│ 📱 iPhone · 2 小时前              │
│                     [踢出]        │
└───────────────────────────────────┘
```

### AUTH-05：IAM SSO Cookie 持久化

**做什么**：浏览器 IAM 会话 7 天有效，二次 OIDC 跳转后免输凭据。

| 文件 | 改动 |
|---|---|
| IAM `iam_http.go` | 登录成功后 `Set-Cookie: iam_session=...; Max-Age=604800; HttpOnly; SameSite=Lax` |
| IAM `LoginView.vue` | 登录表单加「7 天内免登录」复选框（默认勾选） |

**效果**：用户第二次点桌面端「登录」→ 浏览器打开 IAM 页 → Cookie 有效 → **0 秒自动跳回**（不显示登录表单）。

---

## 五、明确不做（当前版本排除）

| 功能 | 排除原因 |
|---|---|
| ~~手机号登录~~ | 不接入手机号体系，当前邮箱+密码够用 |
| ~~生物识别（指纹/Face ID）~~ | 不引入新原生依赖；自动登录已解决重启痛点 |
| ~~扫码登录桌面~~ | 需手机端加相机权限+扫码 UI+WS 推送，工程量大收益边际 |
| ~~魔法链接~~ | 需邮件服务+异步流程，当前密码登录无障碍 |
| ~~企业 SSO（SAML）~~ | 无企业客户需求 |
| ~~社交登录（微信/Google）~~ | 无第三方 OAuth 应用注册 |

## 六、工作量与排期

| 需求 | 改动文件数 | 新文件 | 预估 |
|---|---|---|---|
| AUTH-01 Refresh 持久化 | 4 改 | 0 | **0.5 天** |
| AUTH-02 静默刷新 | 4 改 | 0 | **0.5 天** |
| AUTH-03 等待页进度 | 2 改 | 0 | **0.5 天** |
| **P0 小计** | **~8 改** | **0** | **1.5 天** |
| AUTH-04 设备管理 | 5 改 | 0 | 1 天 |
| AUTH-05 SSO Cookie | 2 改 | 0 | 0.5 天 |
| **P1 小计** | **~7 改** | **0** | **1.5 天** |
| **总计** | **~15 文件改动** | **0 新文件** | **3 天** |

## 七、安全红线

1. refresh_token 与 access_token **同级别保护**——只进 Keychain/SecureStore
2. 每次刷新后 **refresh_token 轮换**（IAM 已实现，旧 token 用后即毁）
3. 登出时**同步清除** refresh_token（`logout` 方法追加一行 `secrets.delete("refresh:...")`）
4. IAM 管理员可**批量撤销**某用户全部会话（已有 `revoke_all_sessions`，设备管理面板调用）
5. 不在 UI/IPC/日志中暴露任何 token 值（现有红线不变）

---

*v2.0 修订：砍掉 6 项非必要功能，保留 5 项高 ROI 改动；全部在现有文件上做增量，零新文件零新依赖。*
