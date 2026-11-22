# ppbChat 登录认证优化需求文档

> 版本：v1.0 · 日期：2026-11-22 · 基于现有 OIDC 认证链路的全面优化设计
> 范围：桌面端（Tauri）+ 手机端（React Native）+ IAM 门户 + 网关

---

## 一、现状与问题

### 1.1 现有基础设施（已存在但未充分利用）

| 组件 | 文件 | 能力 | 利用程度 |
|---|---|---|---|
| 桌面 Keychain 存储 | `authstore.rs` | token 安全存取（keyring v4） | ✅ 已用 |
| 桌面自动登录逻辑 | `session.rs::try_autologin` | 重启后读 Keychain 验活 | ⚠️ 部分（OIDC token 过期即失效） |
| 桌面登录偏好 | `login_preferences.rs` | auto_login/remember_password 标志 | ⚠️ OIDC 路径未写入 |
| OIDC refresh_token | `iam_oidc.rs:135` | IAM 返回 refresh_token | ❌ **未使用**——收到后丢弃 |
| IAM 刷新端点 | `iam_http.go:603` | TokenRequestByRefreshToken | ❌ 客户端未调用 |
| 手机 SecureStore | `secureStore.ts` | token 持久化 | ✅ 已用 |
| 手机自动登录 | `LoginScreen.tsx` | 启动时尝试恢复 | ⚠️ 同桌面——token 过期即失败 |

### 1.2 核心问题链

```
用户登录 → OIDC → 获得 access_token（短有效期）+ refresh_token（未使用）
                                    ↓
              access_token 过期（约 1 小时）
                                    ↓
              try_autologin 调 /me → 401
                                    ↓
              降级登录页 → 用户重新走完整 OIDC → 体验断裂
```

### 1.3 用户旅程对比

| 场景 | 当前 | 主流产品 | 差距 |
|---|---|---|---|
| 首次登录 | ~15 秒（浏览器跳转+输入凭据+回跳） | ~5 秒 | 3 倍慢 |
| **重启客户端** | **~15 秒（重新走 OIDC）** | **0 秒（自动登录）** | **∞ 倍差** |
| Token 过期后 | ~15 秒（重新走 OIDC） | 0 秒（静默刷新） | 同上 |
| 体验上下文切换 | 桌面→浏览器→桌面（认知断崖） | 内嵌 WebView 或零跳转 | 体验差 |

---

## 二、优化方案

### P0：自动登录（Token 持久化 + 静默刷新）

#### 需求 AUTH-01：OIDC Refresh Token 持久化

**目标**：OIDC 登录成功后，将 refresh_token 与 access_token 一并存入 Keychain/SecureStore。

**改动点**：

| 端 | 文件 | 改动 |
|---|---|---|
| 桌面 Rust | `iam_oidc.rs` | OIDC 兑换成功后，将 `refresh_token` 传入 `establish_persistence` |
| 桌面 Rust | `session.rs::login_with_oidc` | `establish_persistence` 增写入 `refresh:{scope}:{memberId}` 键 |
| 桌面 Rust | `authstore.rs` | 新增 `save_refresh/load_refresh/delete_refresh` 三方法 |
| 手机端 | `rnApi/iamChannelRn.ts` | OIDC 回调后提取 refresh_token 传入 secureStore |
| 手机端 | `rnApi/secureStore.ts` | StoredCredentials 结构体加 `refreshToken?: string` |

**验收**：
- [ ] OIDC 登录后 Keychain 中可查到 `refresh:{scope}:{memberId}` 键
- [ ] 手机端 SecureStore JSON blob 含 `refreshToken` 字段
- [ ] 登出时 refresh_token 同步清除

#### 需求 AUTH-02：静默 Token 刷新

**目标**：access_token 过期时，用 refresh_token 向 IAM 换新 token，用户零感知。

**流程**：
```
try_autologin
  → /me 返回 401（token 过期）
  → 读 Keychain refresh_token
  → POST /iam/api/v1/token (grant_type=refresh_token)
  → 成功：新 token 写入 Keychain → 重试 /me → 登录恢复
  → 失败（refresh_token 也过期/被撤销）：降级登录页
```

**改动点**：

| 端 | 文件 | 改动 |
|---|---|---|
| 桌面 Rust | `session.rs` | `try_autologin` 中 401 分支加入 refresh 逻辑 |
| 桌面 Rust | `httpapi.rs` | 新增 `refresh_iam_token()` 方法 |
| 桌面 Rust | `login_preferences.rs` | OIDC 登录成功后置 `auto_login = true` |
| 手机端 | `rnApi/iamChannelRn.ts` | 自动登录路径加 refresh 分支 |

**IAM 无需改动**——`/iam/api/v1/token` 的 `grant_type=refresh_token` 已支持。

**验收**：
- [ ] 桌面端：登录 → 关闭 → 重启 → 自动进入主界面（不弹浏览器）
- [ ] 手机端：同上
- [ ] refresh_token 撤销后（登出/管理员踢）：降级登录页
- [ ] 刷新过程中 UI 无闪白（静默完成）

#### 需求 AUTH-03：等待页实时进度反馈

**目标**：OIDC 等待期间，桌面端显示四态进度而非黑盒。

**状态机**：
```
[●]──→[●]──→[●]──→[●]──→ 登录成功
打开   等待   收到   正在
浏览器  授权   回调   登录
```

**改动点**：

| 端 | 文件 | 改动 |
|---|---|---|
| 桌面 Rust | `iam_loopback.rs` | 回调到达时 emit `iam://progress` 事件（阶段=3） |
| 桌面 Vue | `LoginOverlay.vue` | 等待卡片改为四步进度条（当前步高亮） |
| 桌面 Vue | `auth/iamChannel.ts` | 监听进度事件更新 UI |

**验收**：
- [ ] 点击登录后可见四步进度指示器
- [ ] 浏览器授权完成时进度自动推进
- [ ] 各步骤有对应文案

---

### P1：体验跃升

#### 需求 AUTH-04：生物识别快捷登录

**目标**：重启后 token 有效时，用 Face ID / Touch ID / Windows Hello 解锁而非直接进入。

**交互流程**：
```
客户端启动 → try_autologin 成功（token 有效）
  → 检查「生物识别锁」开关（默认关）
  → 开关开 → 弹生物识别 → 通过 → 进入主界面
  → 开关关 → 直接进入主界面（现状）
```

**改动点**：

| 端 | 文件 | 改动 |
|---|---|---|
| 桌面 Rust | `commands.rs` | 新增 `desktop_biometric_available/desktop_biometric_prompt` |
| 桌面 Vue | `App.vue` | auto-login 成功后调生物识别 |
| 手机端 | `LoginScreen.tsx` | `expo-local-authentication` 集成 |
| 设置 | `SettingsScreen.vue` | 新增「生物识别锁」开关 |

#### 需求 AUTH-05：手机扫码登录桌面端

**目标**：桌面端显示二维码 → 手机扫码确认 → 桌面自动登录（微信范式）。

**交互流程**：
```
桌面端登录页
  ├── [使用 IAM 账号登录] （现有 OIDC）
  └── [手机扫码登录] ← 新增
        ↓
    显示二维码（WebSocket 实时待确认）
        ↓
    手机端扫码 → 弹确认「是否在桌面端登录？」
        ↓              ↓
      [确认]          [拒绝]
        ↓              ↓
    桌面收到 token    桌面显示「已拒绝」
    自动登录
```

**改动点**：

| 层 | 改动 |
|---|---|
| IAM | 新增 `POST /iam/api/v1/qrcode/create`（生成一次性 QR token） |
| IAM | 新增 `POST /iam/api/v1/qrcode/confirm`（手机端确认，返回授权码） |
| WS | 新增 `qr.login` 推送类型（桌面端监听） |
| 桌面 | `LoginOverlay.vue` 加扫码 tab + 二维码渲染 + WS 监听 |
| 桌面 | `session.rs` 新增 `qr_login_wait` 方法 |
| 手机 | 联系人页或设置加「扫一扫」入口 → `expo-camera` 扫码 → 确认弹窗 |

#### 需求 AUTH-06：IAM SSO Cookie 持久化

**目标**：浏览器 IAM 会话持久化，二次 OIDC 跳转后免输凭据直接回调。

**改动点**：

| 层 | 文件 | 改动 |
|---|---|---|
| IAM | `iam_http.go` | 登录成功后 Set-Cookie 加 `Persistent-Authorization`（HttpOnly，MaxAge=7 天） |
| IAM | session 校验逻辑 | 优先查持久 Cookie，回退短期会话 |
| IAM | `LoginView.vue` | 登录页加「记住我 7 天」复选框 |

---

### P2：长期竞争力（概述，后续详设）

#### 需求 AUTH-07：邮箱魔法链接（无密码登录）
#### 需求 AUTH-08：多设备同步登录确认
#### 需求 AUTH-09：设备管理面板（已登录设备列表+远程踢出）
#### 需求 AUTH-10：企业 SSO（SAML/OIDC 联邦）

---

## 三、安全红线（所有优化不得突破）

1. **refresh_token 不出 Rust/原生层**——与 access_token 同等保护级别
2. **Keychain/SecureStore 是唯一持久化面**——不进 SQLite/localStorage/IPC
3. **refresh_token 轮换**——每次使用后 IAM 返回新 refresh_token，旧的立即失效
4. **设备指纹绑定**（P1+）——refresh_token 与设备标识绑定，异地使用触发重新认证
5. **登出即撤销**——客户端登出时调 IAM revoke，服务端销毁 refresh_token 链

## 四、非功能需求

| 指标 | 目标 |
|---|---|
| 自动登录成功率 | > 99%（refresh_token 有效期内） |
| 静默刷新延迟 | < 500ms |
| 重启到主界面 | < 1.5 秒（含 token 验证） |
| 扫码登录全流程 | < 5 秒 |

## 五、实施排期建议

| 批次 | 需求 | 预估 |
|---|---|---|
| 第 1 批 | AUTH-01 + AUTH-02 + AUTH-03（P0 全部） | 2 天 |
| 第 2 批 | AUTH-04 + AUTH-06 | 3 天 |
| 第 3 批 | AUTH-05（扫码） | 3 天 |
| 第 4 批 | P2 按需 | — |

---

*本文档基于 2026-11-22 全面分析产出，基于现有 OIDC 链路基础设施，不推翻现有安全架构。*
