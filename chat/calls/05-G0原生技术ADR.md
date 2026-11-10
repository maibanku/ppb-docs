# G0 原生技术原型 ADR

日期：2026-11-10。状态：进行中（构建/验证逐项落定后更新「验证状态」列，未验证项不得标通过）。

依据：02-架构接口与库表.md §2 原生技术门槛、03-实施任务与验收.md G0。本文是 G0 阶段的架构决策记录：先验证、后铺开，任何一条门槛未通过不得把无功能入口接到生产。

## ADR-1 原生 RTC 技术栈与第三方依赖边界

**决定**：客户端原生通话采用 LiveKit Rust SDK（`livekit = "=0.10.1"`），在独立验证程序 `ppb-chat/tools/rtc-probe` 先行验证，不直接给现有桌面 Cargo 增加大依赖。

**第三方原生依赖事实**（不得声称纯 Rust）：
- `livekit 0.10.1` → `webrtc-sys 0.3.53` → 构建时从官方 GitHub release `livekit/rust-sdks@webrtc-a545de4` 下载 `webrtc-mac-arm64-release.zip`（约百MB级）预编译原生 WebRTC 库（C++，含 boringssl 等），链接进二进制。
- 下载通道为主机直连 GitHub CDN；Docker daemon 代理失效不影响该路径（cargo 走主机网络）。构建慢是 CDN 限速，不是死锁；已核实字节持续增长后不杀构建。
- 本仓不编写自有 C++ 业务代码；「去除 C++」的边界=不手写 C++，SDK 底层原生依赖如实披露。
- 服务端锁定 LiveKit server 1.13.11 / Egress 1.15.0（镜像 digest 固定，见 deploy/rtc/README.md）；Go 侧用官方 `livekit/protocol/auth v1.39.3` 签发短期凭证。

**被否方案**：WebView 内 JS SDK——违反「业务 token/媒体凭证不进 WebView」的既有架构原则，若要采用须另立 ADR 重定义凭证边界，不悄悄绕过。逐帧 base64 搬视频——30fps 视频经 Tauri event 转发不可行，G0 验证项明确排除。

## ADR-2 凭证与媒体权限边界

**决定**：
- API secret 只存在 ppb-base 服务端（`deploy/rtc/.local/credentials.json`，0600，Git 忽略）与 server-im 配置；不进 Vue、不进前端资源、不进日志。
- 客户端经 PPB 业务接口（会话成员/设备权限校验通过后）换取短期入会 JWT（≤2 分钟，限定房间+成员+设备；音频通话凭证禁发布摄像头——server-pkg/rtc JoinToken 已实现），由 Tauri Rust 持有；重连需重新鉴权。
- SFU webhook（媒体事实、录制事实）验签后才可信；业务状态机（internal/call/domain.go）只接受 `EventSourceMediaWebhook`/`EventSourceRecordingWebhook` 声明媒体/录制事实，客户端单方声明一律拒绝。

## ADR-3 通话卡片消息类型预留

**决定**：`msg_type` 1–8 已占用（8=富文本），9 预留给语音消息；通话卡片预留 `msg_type = 10`，内容仅最小信息（类型/结果/时长摘要），事实源是 im_call 表，卡片以 callBizKey 关联，客户端不得以卡片存在推断真实接通。G3 实施时在此登记。

## G0 验证矩阵（真实环境，非容器 ready 即算）

| 验证项 | 手段 | 状态 |
|---|---|---|
| 信令/房间 API（Go 适配器） | `go run ./cmd/rtc-smoke` 真实 create/delete + 短期凭证 | ✅ PASS（2026-11-10，Codex 轮） |
| Rust SDK 构建（原生库下载/链接） | `cargo build --manifest-path tools/rtc-probe/Cargo.toml` | 进行中 |
| 双端原生信令入会 | `local.py native-probe`：两参与者真实 connect 同房间 | 待构建完成 |
| 麦克风采集+发布+对端订阅（音频可听） | probe 扩展：Device 源发布 mic 轨，对端订阅并确认轨到达 | 待做 |
| 摄像头采集+渲染（不经逐帧 base64） | probe 扩展：视频轨发布/订阅，原生渲染句柄验证 | 待做（需系统权限，预期 macOS TCC 提示） |
| 离开释放设备 | 断开后确认轨关闭/设备释放、SFU 房间清理 | 待做 |
| Egress 真实音频产物 | 真实发布音频后启动 room audio egress，产物落 .local/recordings 并可播放 | 待做（G4 前置） |

## 环境边界（如实记录）

- 本机回环拓扑：仅同机客户端可用（127.0.0.1:7880/7881/7882）；未部署 TURN，不宣称公网穿透。
- macOS 麦克风/摄像头权限（TCC）：CLI 探测进程首次采集会触发系统授权，若被拒将记录证据并继续其余验证。
- Windows 差异：本机无 Windows 环境，G0 仅覆盖 macOS arm64；Windows 验证留待具备环境后补做，不声称已完成。
