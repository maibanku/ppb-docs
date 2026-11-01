# AI 相机 · Claude Code 执行计划

| 项目 | 内容 |
|---|---|
| 版本 | V2.4 · 2026-11-01 |
| 性质 | **需求更新后的执行计划**；下表代码任务状态 = **待执行**（实际进度只看[实施现状与验证记录](实施现状与验证记录.md)）；唯一例外为文档任务 T01，随本轮文档校验标完成 |
| 配套 | [产品功能设计](../产品功能设计.md) · [AI 构图交互与模块架构](../tech/AI构图交互与模块架构.md) · [技术大纲](../tech/技术大纲.md) · [需求追踪矩阵](../ac/需求追踪矩阵.md) |
| 决策依据 | [ADR-1101](../adr/调整记录.md) |

---

## 0. 执行规则（先读）

1. **首个代码任务限定为 T02 NetworkKit 模板客户端**（纯包内实现，不改 App/Features）。当前工作树存在其他任务的未提交修改（App/Features 在改、灵感页删除中），**不得并发覆盖**；凡涉及 `App/`、`Features/` 的任务（T04、T05 接线、T08–T12、T18）必须等在改任务收口（T00 完成）后再动。
2. 每个任务只写「文件范围」列出的路径；越界改动视为执行失败。
3. 验收 = 可执行的检查（测试/编译/静态断言），**不得以「看起来对」或性能目标充当验收**；性能目标值（冷启 ≤1.2s 等）只进验收记录模板，不进任务验收。
4. 状态标注诚实：做完改「已执行」前必须有对应验证证据并同步到[实施现状](实施现状与验证记录.md)；不得伪造完成、不得声称已真机验证或已接通云 AI。
5. 仓库边界：iOS 端只改 `ppb-camera/camera-ios-app/**`；服务端只改 `ppb-base/server-camera/**`、`server-gateway/**`（如需）；后台只改 `ppb-camera/camera-manager-web/**`。**不碰 ppb-chat，不新建 React/Postgres 工程。**

## 任务总表

依赖图（→ 表示「依赖其完成」）：

```
T00 四Tab整合 ─┬→ T04 → T05 → T07 → T08 → T09 → T10/T11 → T12
               └→ T18(可与轨道B/C并行)
T01 → T02 → T03 → T04
T13 → T14 → T15 → T16 → T17 → T18
T14 → T19
T20 独立预留(默认不排)
全轨道 → T21 验收
```

| ID | 任务 | 对应 | 状态 |
|---|---|---|---|
| T00 | 工作树整合：恢复四 Tab | FS-01/06/10 | 待执行 |
| T01 | 文档基线同步（本文档族） | 全部 | 已完成（本轮校验） |
| T02 | **NetworkKit 模板客户端（首个代码任务）** | FS-01/06 | 待执行 |
| T03 | StorageKit 模板缓存 | FS-01/06 | 待执行 |
| T04 | 模板选择层接缓存 + 灵感页 | FS-01/06 | 待执行 |
| T05 | GuidanceEngine 引导状态机 | FS-03 | 待执行 |
| T06 | PoseKit 端侧检测 | FS-03/04 | 待执行 |
| T07 | 帧流水线与坐标映射接线 | FS-03/04 | 待执行 |
| T08 | 拍摄模式（倒计时/连拍） | FS-05 | 待执行 |
| T09 | 会话选片 | FS-07 | 待执行 |
| T10 | StyleKit 调色内核 | FS-08 | 待执行 |
| T11 | 调色页 UI | FS-08 | 待执行 |
| T12 | 相册 add-only 导出增强 | FS-08 | 待执行 |
| T13 | PrivacyKit 授权与上传守卫 | FS-02/11 | 待执行 |
| T14 | server-camera 分析/额度/账号 RPC | SRV | 待执行 |
| T15 | SceneIntelligence 云任务客户端 | FS-02 | 待执行 |
| T16 | EntitlementKit 额度与 IAP | FS-10 | 待执行 |
| T17 | AccountKit 登录绑定对接 | FS-10 | 待执行 |
| T18 | 我的页（四 Tab 之四） | FS-10/11 | 待执行 |
| T19 | 管理后台 API 落地 | ADM | 待执行 |
| T20 | 自动曝光/变焦（预留，默认不排） | — | 待执行 |
| T21 | 验收执行与记录 | 全部 | 待执行 |

---

## 轨道 0：整合与基线

### T00 工作树整合：恢复四 Tab（拍照/灵感/作品/我的）

- **对应**：FS-01/06/10、ADR-1101
- **前提**：ppb-camera 当前未提交改动（三 Tab 方案、删除 `Features/Inspire/`）由其所属任务收口提交或明确废弃后，本任务方可执行；执行前先 `git status` 确认工作树干净。
- **文件范围**：`ppb-camera/camera-ios-app/App/CameraApp.swift`、`App/AppEnvironment.swift`（如需）、`Features/Inspire/**`（恢复/重建）、`Features/Settings/**`（「我的」页承载）、`Tests/CameraAppTests/**`、`CameraApp.xcodeproj/project.pbxproj`（恢复 Inspire 目标引用）
- **输入**：[产品功能设计 §2](../产品功能设计.md)（四 Tab 顺序与默认页）、架构文档 §6.1、被删除前的 `InspireView.swift`（git 历史）
- **输出**：四 Tab 常驻（拍照/灵感/作品/我的，默认拍照）；灵感页恢复且可从模板库选中模板；「我的」页聚合 IAM 账号区 + 设置内容；调整面板保留目的/模板/构图辅助开关入口
- **依赖**：在改任务收口（外部）
- **验收**：`xcodebuild test`（iOS 模拟器）通过，含新增断言：Tab 枚举顺序 = capture/inspire/gallery/profile、默认 selectedTab = capture；灵感页存在且「去拍同款」可切换到拍照 Tab
- **不做项**：不改 Packages；不做模板网络加载（灵感页先用内置模板数据）；不动 CaptureView 现有构图辅助逻辑

### T01 文档基线同步

- **对应**：全部
- **文件范围**：本任务即 2026-11-01 已交付的文档族（产品功能设计/架构文档/本计划/现状记录 + README/PRD/界面规范/FS-01/06/10/矩阵/ADR 追加）
- **输入/输出/验收/不做项**：见[报告与 ADR-1101](../adr/调整记录.md)；本条目仅作追踪锚点，**不重复执行**
- **状态**：已完成——随本轮文档交付与校验关闭（全部任务中唯一非「待执行」项，记录见实施现状 §1）

## 轨道 A：客户端本地闭环（T02–T12）

### T02 NetworkKit 模板客户端 ⭐ 首个代码任务

- **对应**：FS-01 §11、FS-06 §11、技术大纲 §7（`GET /v1/templates` 契约）
- **文件范围**：仅 `ppb-camera/camera-ios-app/Packages/NetworkKit/**`（Sources/Tests/Package.swift）
- **输入**：网关已放行的 `GET /api/v1/camera/templates?since=`（匿名公开内容）；proto/技术大纲 §7.1 响应结构（revision、增量、下架墓碑）；错误码口径（401/403/409/422/429/5xx + 业务 code）
- **输出**：
  1. `TemplateCatalogClient`（actor）：`fetch(since:revision:) async throws -> TemplateCatalogDelta`；请求复用（URLSession 注入）、超时与重试策略（可注入 clock/URLSession 便于测试）
  2. `TemplateCatalogDelta` 模型：revision、新增/更新模板、下架墓碑、`needsFullRefresh` 标记
  3. 错误域 `NetworkError`：区分网络失败 / HTTP 状态 / 业务 code，不把 401 当余额类错误
  4. 包内 swift-testing 用例：增量解析（含墓碑）、全量刷新指令、错误映射、重试边界
- **依赖**：无（T01 文档已交付）
- **验收**：`swift test` 在 NetworkKit 包内通过（macOS 宿主）；零跨包依赖；**不修改 App/Features 任何文件**（与在改任务零冲突）
- **不做项**：不接 UI、不落盘缓存（归 T03）、不做登录/额度/分析接口、不处理图片资源下载（样片 URL 透传即可）

### T03 StorageKit 模板缓存

- **对应**：FS-01 §11、FS-06 §11
- **文件范围**：`Packages/StorageKit/**`
- **输入**：T02 的 `TemplateCatalogDelta`；技术大纲 §6（Template 字段：id/revision/purposeId/assetHashes/poseTemplateId/status）
- **输出**：`TemplateStore`——LRU 缓存（30 天）、增量合并（含墓碑标记「已下架」）、`needsFullRefresh` 全量替换、3 张内置兜底模板常驻（标「离线模板」）、收藏读写（全本地）
- **依赖**：T02
- **验收**：包内测试：增量合并/墓碑后不可选但收藏可见、过期 LRU 清理、离线返回兜底集
- **不做项**：不做图片缓存（样片图缓存另行任务）；不写 UI

### T04 模板选择层与灵感页接缓存

- **对应**：FS-01、FS-06
- **文件范围**：`Features/Capture/TemplatePickerSheet.swift`、`Features/Inspire/**`
- **输入**：T03 `TemplateStore`、AppEnvironment 偏好（目的/模板记忆）
- **输出**：调整面板模板层与灵感页共用数据源；灵感页分类 chips/瀑布流/收藏/去拍同款/已下架态；静默刷新不阻塞首屏
- **依赖**：T00、T03
- **验收**：模拟器测试：离线可浏览、下架模板标「已下架」且「去拍同款」禁用、去拍同款正确携带 templateId 并切到拍照 Tab
- **不做项**：不实现推荐算法；不做分享

### T05 GuidanceEngine 引导状态机

- **对应**：FS-03、技术大纲 §5、G3
- **文件范围**：`Packages/GuidanceEngine/**`、`Packages/SharedModels/**`（如需事件类型）
- **输入**：架构文档 §3.2 状态机（idle/candidate/active/cleared/cooldown + escalate）；FS-03 判定规则表与参数（candidate 1.5s / 解除驻留 1.0s / 冷却 2s / 升级 6s；优先级链）
- **输出**：时间可注入（monotonic clock）的纯逻辑状态机；输入=指标观测流（每个问题的触发/解除布尔），输出=`GuidanceEvent`（建议上屏/达标/升级/冷却）；无检测输入时保持 idle（结构上不可能输出假达标）
- **依赖**：无硬依赖（可与 T02 并行，但按本表顺序执行）
- **验收**：包内测试覆盖触发/解除/滞回方向/冷却/升级一次/微抖 ±2° 60s 无重复激活（注入时钟加速）；同屏仅一条
- **不做项**：不做检测（观测由 T06 提供）；不做 UI；不接云建议（T15）

### T06 PoseKit 端侧检测

- **对应**：FS-03/04、技术大纲 §4
- **文件范围**：`Packages/PoseKit/**`
- **输入**：CameraCore 帧接口（在 T07 接线前先以协议桩开发）；FS-04 规则（置信度 <0.6 关节不判、左右镜像、多人只跟主体）
- **输出**：`SubjectObserver`（人体外接框流：无主体/出框/大小/头顶裁切指标）、`PoseObserver`（关节点流 + 平滑 + 步骤匹配）；输出均带 I 域坐标与置信度；低置信静默（不产生建议事件）
- **依赖**：建议在 T05 后（复用其事件语义）
- **验收**：包内测试：指标换算（含 §4.3 逆映射的纯函数部分）、置信度门控、丢帧只保留最新
- **不做项**：不在真机标定性能（真机指标归 T21）；不做云侧

### T07 帧流水线与坐标映射接线

- **对应**：FS-03/04、技术大纲 §4、架构文档 §4
- **文件范围**：`Packages/CameraCore/**`（帧输出，不改快门路径）、`Features/Capture/CaptureView.swift`（覆盖层与建议条）、`Packages/GuidanceEngine/**`（如需胶水）
- **输入**：T05 + T06；`AspectFillCropMapping`（已在 CaptureView，需抽为可复用纯函数或引用同源实现）
- **输出**：预览帧 → 检测（15fps 目标、丢旧帧）→ 状态机 → 双路输出：`GuidanceEvent`（文案/触觉）+ 有界 `OverlaySnapshot`（轮廓/箭头/检测框）；**前摄镜像、设备方向、预览裁切、拍摄比例四项坐标归一**；过热降级链（关轮廓→10fps→仅参考线）
- **依赖**：T00、T05、T06
- **验收**：模拟器/合成帧测试：前摄镜像下检测框位置正确；建议上屏与参考框坐标一致；切 Tab/后台暂停检测；快门路径行为与无检测时完全一致（G4 回归）
- **不做项**：不做云分析；不改 WYSIWYG 裁切语义

### T08 拍摄模式（倒计时/连拍）

- **对应**：FS-05
- **文件范围**：`Features/Capture/**`（模式条）、`Packages/CameraCore/**`（连拍会话，如需）
- **输入**：FS-05 规则（3s 倒计时可取消、连拍 3 张目标间隔 400ms、快门 ≤50ms 反馈目标）
- **输出**：模式条（单拍/3s/连拍）+ 倒计时覆盖层 + 连拍会话张数角标；来电/切后台无半张文件
- **依赖**：T00（CaptureView 收口）
- **验收**：模拟器测试连拍写出独立目录（无覆盖）；倒计时取消不落片；飞行模式全流程可拍
- **不做项**：不实现假变焦档位/闪光（未实现不显示）；不承诺快门时延实测达标（归 T21）

### T09 会话选片

- **对应**：FS-07
- **文件范围**：`Features/Picker/**`、`Packages/GalleryKit/**`
- **输入**：FS-07 规则（预选分 0.5/0.3/0.2、相似组折叠、永不自动删除、30 张最多 3 组）
- **输出**：会话网格 + 全屏对比 + 差异 chips + 选 ≤3 张去调色；标记仅为建议（删除永远手动确认）
- **依赖**：T08（连拍数据形态）、T00
- **验收**：测试：标记不触发任何自动删除；低光全糊给解释文案；端侧离线完成
- **不做项**：不做云选片；不做人脸识别入库

### T10 StyleKit 调色内核

- **对应**：FS-08
- **文件范围**：`Packages/StyleKit/**`
- **输入**：6 风格 LUT 资产、技术大纲 §6（EditRecipe：photoId/styleId/lutVersion/recipeVersion/adjustments）
- **输出**：LUT 应用与预览渲染（≤100ms 切换目标，仅作目标）、配方序列化（recipe.json）、快速连点合并渲染末次为准、保留 EXIF
- **依赖**：无硬依赖（可与 A 轨并行）
- **验收**：包内测试：原片字节不变（哈希断言）、配方重放确定性、6 风格逐一渲染非空
- **不做项**：无滑杆无参数面板；不做商店；不做云渲染

### T11 调色页 UI

- **对应**：FS-08
- **文件范围**：`Features/Editor/**`
- **输入**：T10；「按住看原片」交互
- **输出**：风格圆点切换 + 按住看原片 + 保存（首次申请 add-only 权限）；权限拒绝引导卡不丢配方
- **依赖**：T10、T00
- **验收**：模拟器测试：切换有 `tick`；拒绝权限路径配方保留；保存成功 toast + success
- **不做项**：不做批量导出

### T12 相册 add-only 导出增强

- **对应**：FS-08/09
- **文件范围**：`Packages/GalleryKit/PhotoExporter.swift`、`Features/Gallery/**`（如需文案）
- **输入**：现有 `PhotoExporter`（实施现状 §2）；FS-09 删除口径（底稿 tombstone 与导出副本无关）
- **输出**：导出仅在系统写入完成后报成功；导出记录（export_state/export_id）去重口径（PRD §14）；删除底稿二次确认文案
- **依赖**：T11
- **验收**：测试：导出成功事件仅一次/photo；删除底稿不影响已导出标记展示
- **不做项**：不做云备份说明实现（仅文案与边界）

## 轨道 B/C：云分析与服务端（T13–T17）

### T13 PrivacyKit 授权与上传守卫

- **对应**：FS-02/11、G5
- **文件范围**：`Packages/PrivacyKit/**`
- **输入**：技术大纲 §7.1（consentVersion）、FS-02 授权卡口径（单帧/用途/保留期/额度）、FS-11（拒绝永不静默改判）
- **输出**：用途授权状态机（unknown/granted/declined/revoked + policyVersion）；`UploadGuard`——无有效授权时抓帧/编码/发送路径全部短路（结构级零上传）；反馈附件授权独立
- **依赖**：无（可与 A 轨并行）
- **验收**：包内测试：declined/revoked 下守卫拒绝一切分析帧出口；版本变更要求重新授权
- **不做项**：不做 UI 卡片（随 T15）；不做网络发送本体

### T14 server-camera 分析/额度/账号 RPC

- **对应**：SRV、技术大纲 §7/§9、database.md
- **文件范围**：`ppb-base/server-camera/**`（handler/service/repo/domain）；如需网关放行调整 `ppb-base/server-gateway/**`（仅 camera 域路由/白名单）
- **输入**：技术大纲 §7.1 端点契约、§9.1 事务约束、[database.md](../tech/database.md) DDL、现有 domain 层（analysis_task/quota/subject 已有模型与测试）
- **输出**：`CreateGuestSession`（匿名主体签发，频控）、`CreateAnalysis`（原子预留 + 单帧接收 + deadline）、`GetAnalysis`、`AckAnalysis`（核销）、`CancelAnalysis`（释放）、`GetQuota`、SMS/Apple 登录绑定（事务合并本期免费额度）；Provider 接口保持可替换（不虚构推理结果，未配置时如实 CAM-9050）
- **依赖**：T13 无关（服务端可先行）；接口冻结需 T15 前完成
- **验收**：Go 测试：同键幂等（同键不同内容 409）、仅剩 1 次并发两任务至多一个预留、ack/cancel 竞争单终态、跨月桶不污染、到期清扫释放；`go test ./...` 通过
- **不做项**：不实现真实推理供应商对接（另列）；不动 im/file/iam 域；不改网关其他域路由

### T15 SceneIntelligence 云任务客户端

- **对应**：FS-02、架构文档 §3.1/§3.3
- **文件范围**：`Packages/SceneIntelligence/**`、`Packages/NetworkKit/**`（分析端点）、`Features/Capture/**`（AI 按钮与建议条接线）
- **输入**：T13 守卫、T14 接口、T05/T07 状态机（云建议经端侧校验落屏）
- **输出**：主动点击 → 授权卡 → 抓帧（长边≤1280/q0.7/去 EXIF；黑帧不上传）→ 任务创建（requestId）→ 3s 预算内查询/ack；超时降级本地建议角标；迟到结果丢弃；额度尽额度卡；离开取景器取消
- **依赖**：T13、T14、T07
- **验收**：集成测试（本地起 server-camera）：超时/取消/幂等各路径额度一致；断网全程快门可用；「analysis_requested 仅在真正创建任务时上报」
- **不做项**：不显示假进度；不自动重发新任务对账（按技术大纲 §7.2 查询终态）

### T16 EntitlementKit 额度与 IAP

- **对应**：FS-10、技术大纲 §9.2
- **文件范围**：`Packages/EntitlementKit/**`
- **输入**：T14 `GET /v1/quota`；StoreKit 2
- **输出**：额度只读缓存（version、fetchedAt、离线标注）；IAP 状态机（取消/待支付/待核验/已入账/退款）待核验如实展示；不凭客户端回调加次数
- **依赖**：T14
- **验收**：测试：缓存只读、服务端版本优先；重复通知幂等展示
- **不做项**：不实现商品定价（发布前决策项）

### T17 AccountKit 登录绑定对接

- **对应**：FS-10
- **文件范围**：`Packages/AccountKit/**`（现有 OIDCClient/IAMAuthSession 之上）
- **输入**：T14 SMS/Apple 端点或 IAM 桥路径（以 server-camera 实际契约为准，先读代码再定）
- **输出**：匿名主体 → 登录绑定（本期额度事务合并由服务端完成）；退出清 token/额度/订单缓存、保留作品；删除账号流程状态查询
- **依赖**：T14
- **验收**：测试：绑定后旧匿名凭据不能另领；A 退出 B 登录无余额残留
- **不做项**：不做云同步

### T18 我的页

- **对应**：FS-10/11、产品功能设计 §10
- **文件范围**：`Features/Settings/**`、`App/**`（路由）、`Features/Theme/**`（如需）
- **输入**：T16、T17；现有 IAMAccountSection/SettingsSheet
- **输出**：四 Tab 之「我的」：IAM 账号区、额度（大数字+进度+更新口径）、权限与隐私（云分析开关：关后构图按钮变本地指导）、存储、反馈、关于；设置与调整面板双入口同源
- **依赖**：T00、T16、T17
- **验收**：模拟器测试：游客全本地功能可达；关闭云分析后零上传路径（与 T13 守卫联动断言）；反馈截图默认不勾
- **不做项**：不展示 P1 灰色占位（云同步等）

## 轨道 D：后台（T19）

- **对应**：ADM、PRD §6
- **文件范围**：`ppb-camera/camera-manager-web/**`、`ppb-base/server-camera/internal/handler/camera_admin_handler.go` 及 service
- **输入**：proto admin RPC；base-manage-web 底座模式；已实现的 Overview/Accounts/Audit/Cost 四接口
- **输出**：模板发布审核流（草稿/复核/发布/下架/恢复 + 版本 diff）、AI 策略版本与回滚、额度补偿双人审批、反馈工单、审计与成本页接真实 API（替换 stub）；未提供的能力不渲染假数据
- **依赖**：T14（账号/额度数据面）
- **验收**：`npm run typecheck && npm run test`（camera-manager-web）；后端 admin 测试：申请人不能审批自己；普通运营不可见分析帧（无此接口）
- **不做项**：不重建 React/Postgres；不做高级仪表盘（P1）

## 预留（T20，默认不排）

- **自动曝光/变焦**：仅当产品再次确认排期才启动；四前提（主动授权/真实反馈/恢复入口/默认不自动拍摄）为验收前置，缺一不发版。文件范围届时另行定义，且只允许在 CameraCore 设备能力层 + 授权卡实现，禁止绕过 PrivacyKit。

## 验收（T21）

- **对应**：ac 体系
- **文件范围**：`ppb-docs/camera/ac/验收执行记录模板.md` 生成实例、`eval/**`
- **输入**：全部前序任务；[验收总则](../ac/00-验收总则与发布门槛.md)、[需求追踪矩阵](../ac/需求追踪矩阵.md)
- **输出**：按矩阵逐项执行的记录（真机性能基线、授权抓包、并发结算、无障碍、飞行模式闭环）；未执行项如实标「未执行」
- **依赖**：全部
- **验收**：记录中不得出现无证据的「通过」；目标指标与实测值分列
- **不做项**：不为了绿表放宽口径

---

## 执行顺序建议（同一会话内）

1. T02（NetworkKit，立即可做，零冲突）→ 2. T05/T10/T13（三个纯包，可先后做）→ 3. 待在改任务收口后 T00 → 4. T03 → T04 → 5. T14 → 6. T06 → T07 → 7. T08 → T09 → 8. T11 → T12 → 9. T15 → T16 → T17 → T18 → 10. T19 → 11. T21。
