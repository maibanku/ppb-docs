# AI 相机 · AI 构图交互与模块架构

| 项目 | 内容 |
|---|---|
| 版本 | V2.4 · 2026-11-01（需求更新文档；架构深化，不推翻[技术大纲](技术大纲.md)） |
| 范围 | AI 构图交互的模块边界、状态机、预览/裁切坐标系、中心点与主体/对焦的区别、端云分工；模块归属以实际仓库代码为准（见[实施现状](../implementation/实施现状与验证记录.md)） |
| 配套 | [产品功能设计](../产品功能设计.md) · [技术大纲](技术大纲.md) · [界面设计规范](界面设计规范.md) · [执行计划](../implementation/Claude-Code执行计划.md) |
| 决策依据 | [调整记录 ADR-1101](../adr/调整记录.md) |

---

## 1. Doka 参考边界（工程口径）

**仅参考「AI 构图交互功能」**：用户表达拍摄意图 → 取景器内给出构图/姿势辅助 → 引导对齐 → 完成拍摄，这一交互模式的信息层级与能力设计。

**不参考**：布局、导航结构、配色、控件样式、图标资产。任何「Doka 有所以我们也放一个」的控件/入口，若无本文档或 FS 细则依据，一律不做（[界面设计规范 §1](界面设计规范.md)）。视觉与尺寸规范仍以界面设计规范为唯一权威。

## 2. 三层递进的 AI 构图交互

实现顺序即依赖顺序（ADR-1101）；每一层都可独立交付且不阻塞快门。

```
L1 本地辅助（无 AI）──→ L2 端侧检测（设备推理）──→ L3 真实云分析（主动授权）
   参考框/网格/中心点        主体+姿态检测                单帧分析+结构化建议
   静态本地指导卡            稳定引导状态机               幂等+额度一致性
```

| 层 | 数据流 | 模块（目标归属） | 诚实边界 |
|---|---|---|---|
| L1 | 纯 UI 几何，零采集零网络 | App/CaptureView（参考框、中心点、网格、指导卡） | 卡片标注「本地指导」；无进度、无达标反馈 |
| L2 | 相机帧 → 端侧检测（Vision）→ 平滑/置信度 → 状态机 → 双路输出（建议事件 + 覆盖层快照） | CameraCore（帧）· PoseKit（检测）· GuidanceEngine（状态机）· DesignSystem（呈现） | 低置信静默（P3）；达标只来自真实判定；过热降级链 |
| L3 | 用户主动点击 + 单帧授权 → 抓帧编码 → 云任务 → 结果校验 → ack 核销 → 建议落屏 | SceneIntelligence · PrivacyKit（授权守卫）· EntitlementKit（额度）· NetworkKit（传输）· server-camera/server-gateway | 未确认不扣；迟到结果丢弃；云结果仍经端侧校验 |

**关键规则**：L3 的云结果只是「候选目标」，落屏前必须经 L2 的现场与置信度重新校验（技术大纲 §5）；L1→L2→L3 任何一层都不得伪造下一层的能力（假进度/假达标为验收红线，[产品功能设计 §12](../产品功能设计.md)）。

## 3. 状态机

### 3.1 构图指导会话总状态（App 层编排）

```
guidanceOff ──点构图按钮──→ localCard(L1)        ← 再点关闭
localCard   ─L2可用──→ engineDriven(L2)          ← L2 不可用保持 L1 并如实标注
engineDriven──点AI分析──→ cloudPending(L3)        ← 融入 L2 呈现，不新建 UI 层
cloudPending──结果确认──→ engineDriven(带云建议)
             └─超时/失败/取消→ engineDriven(端侧建议 + 「本地建议」角标)
任何状态 ──离开取景器/切后台──→ guidanceOff（取消云任务、丢弃迟到结果）
```

约束：

- 快门、变焦、前后摄切换在指导状态机的任何 AI 状态下保持可用（G4）；指导状态机无权禁用拍摄控件。此限定仅针对 AI 指导状态，不覆盖相机权限未授予、硬件不可用、拍摄处理中等真实约束（如实禁用或提示，见产品功能设计 §1）。
- `cloudPending` 的加载反馈只描述真实阶段（「正在看现场…」→「快了，再看一下构图…」按真实耗时切换），禁止无任务在途时的假转圈。
- 从 `cloudPending` 退出后回到的是**当前** L2 现场，不重放旧建议。

### 3.2 单问题引导状态机（GuidanceEngine，L2 核心，技术大纲 §5）

```
idle → candidate(连续1.5s满足) → active(上屏) → cleared(连续1.0s解除区 + 驻留)
                                    ├→ escalate(6s未解除，升级文案一次)
                                    └→ cooldown(同类2s)
```

- 时间用可注入单调时钟（G3 可测）；触发/解除阈值按各自方向定义滞回（判定表见 [FS-03](../pr/FS-03-机位引导.md)）。
- 同屏仅 1 条建议（P1）；优先级：无主体 > 出框 > 大小 > 倾斜 > 头顶裁切 > 逆光 > 姿势。
- **达标（cleared 的成功反馈）只能由真实检测流驱动**；检测未运行（如权限受限、过热降级到仅参考线）时状态机停在 idle/candidate，不得伪造 active→cleared 转移。这是「不得假达标」的状态级保证。

### 3.3 云任务状态（L3，服务端权威，技术大纲 §7/§9）

```
created → reserved → running → ready → committed（ack 确认，核销）
                   ↘ failed / cancelled / expired → released（释放额度）
```

- 客户端只做：创建（带 requestId）、查询、ack、cancel；本地 Task.cancel 只是停止等待，另发 cancel 或依赖到期清扫。
- ack 与 cancel 竞争由服务端行锁串行决定终态；同 `(subjectId, requestId)` 幂等。

## 4. 预览与裁切坐标系（权威定义）

取景器坐标是全链路最容易漂移的部分，本文固定四个坐标域与换算规则（实现参照 `CaptureView.swift` 中的 `FinderGuideGeometry` / `CaptureLayout` / `GuideLayout` / `AspectFillCropMapping` / `WYSIWYMCaptureCrop`，见[实施现状 §2](../implementation/实施现状与验证记录.md)）。

### 4.1 坐标域

| 域 | 定义 | 用途 |
|---|---|---|
| S 屏幕域 | 预览层全屏 bounds（points） | 控件、参考框绘制 |
| G 参考框域 | 3:4 矩形，S 的子矩形 | 构图辅助绘制、裁切窗口 |
| I 图像域 | upright（EXIF 方向归一后）像素 | 检测输出、裁切、成片 |
| D 设备域 | 相机输出原始方向/镜像（前摄镜像） | 仅在采集与归一层出现，UI 不直接使用 |

### 4.2 参考框几何（S → G）

- 比例固定 3:4（宽:高）；水平居中，左右最小边距 16pt。
- 垂直方向在 `[topReserve, height − bottomReserve]` 预留带内取**能放下的最大 3:4 矩形**（预留带 = 安全区 + 顶部调整图标行 + 底部快门/工具/导航行），保证参考框不被控件与手势区遮挡。
- 绘制与裁切**共用同一份布局快照**（GeometryReader 采集一次，Preference 回传状态），禁止两处各自计算。

### 4.3 预览 → 像素映射（S/G → I）

预览层为 aspectFill：3:4 画面填满更瘦长的屏幕时左右溢出。映射公式：

```
scale   = max(layerW / imageW, layerH / imageH)      // aspectFill 缩放
offsetX = (imageW·scale − layerW) / 2                 // 居中裁切偏移
imgRect = ((g.minX + offsetX)/scale, (g.minY + offsetY)/scale,
           g.width/scale, g.height/scale)             // 参考框(裁剪到层内)对应像素矩形
```

规则：

- 参考框先与预览层 bounds 求交（防越界）；交集为空 → 几何无效。
- 检测输出（I 域）反向上屏走同一公式的逆变换；**任何一处单独实现映射都视为缺陷**。

### 4.4 拍摄 WYSIWYG 裁切（所见即所得）

```
原片字节 → 解码 → EXIF 方向归一(upright) → §4.3 映射取整(integral) → 与图像边界求交
→ 裁切 → 重编码(HEIC 优先 q0.9，失败回退 JPEG q0.95) → 3:4 成片
```

- 任一步失败：**回退保存原图并如实提示**，拍摄成功优先于裁切精确，不吞照片。
- 圆角取景只是视觉遮罩，导出图像恒为矩形（界面设计规范 §2）。
- **前摄镜像与设备方向**：D→I 归一是 L2 坐标正确性的前置条件（技术大纲 §4「坐标映射必须覆盖前摄镜像、方向、预览裁切和拍摄比例」）；L1 的 UI 叠加不依赖镜像，但 L2 检测框上屏必须先做镜像/方向归一，属 L2 任务的验收项。

### 4.5 中心点落点（G 域）

中心点位置 = G 域几何中心 `(g.midX, g.midY)`，**不是** S 域（整屏）中心。参考框因预留带而垂直偏移时，两者不同——这是「中心点默认在实际 3:4 参考框中心」要求的几何含义。

## 5. 中心点 vs 主体检测 vs 对焦

三者是最易混淆的概念，严格正交、互不冒充：

| 概念 | 是什么 | 数据来源 | 生命周期 | 是否进原片 |
|---|---|---|---|---|
| **中心点**（CenterAim） | 3:4 参考框几何中心的静态标记（小圆点+细环+十字刻线） | 纯 UI 几何，无任何感知 | 用户开关控制（默认开）；`allowsHitTesting(false)`、VoiceOver 隐藏 | 否 |
| **主体检测**（L2） | 帧流中人体/主体的实时外接框与关键点 | 端侧 Vision 推理 + 平滑 | 仅检测运行期；输出进 OverlaySnapshot，驱动引导与参考 | 否（仅 UI 覆盖层） |
| **对焦/曝光** | 设备控制域（AVFoundation focus/exposure） | 用户点按（如实现 tap-to-focus）或系统自动 | 相机会话控制，属 CameraCore 设备能力 | 影响成像参数，不是内容叠加 |

红线：

1. 中心点**不是对焦点**：点中心点不触发对焦；点按对焦（若实现）属设备控制，反馈必须是系统/真实对焦动画，不得复用中心点图形。
2. 中心点**不是识别结果**：无检测运行时中心点照常显示，但不得出现任何「已识别主体」暗示（无检测框、无高亮跟随）。
3. 主体检测框**只在 L2 检测真实运行时出现**；置信度不足时收起检测框（P3 静默），不得保留残影冒充识别。
4. 三者的 UI 图形必须可区分：中心点恒为静态几何符号；检测框随主体移动；对焦反馈来自系统语义。

## 6. 模块边界（按实际仓库归属）

### 6.1 ppb-camera / camera-ios-app（Swift，iOS 17+）

```
App/            CameraApp（装配、四 Tab 路由、生命周期）、AppEnvironment
                （相机激活仲裁、偏好、内置模板库 BuiltInTemplateRepository）
Features/
  Capture/      取景器、参考框/网格/中心点、构图按钮与本地指导卡、快门、
                调整面板、模板选择层（TemplatePickerSheet）
  Inspire/      灵感页（模板库瀑布流、收藏、去拍同款）★ 四 Tab 之一
  Gallery/      作品页、照片查看
  Picker/       会话选片
  Editor/       调色页
  Settings/     设置内容、IAM 账号区（「我的」Tab 复用）
  Theme/        浅色页主题
Packages/（13 个，见技术大纲 §3 命名）
  实包：CameraCore、AccountKit、StorageKit、SharedModels、DesignSystem、GalleryKit
  marker（待实现）：NetworkKit、GuidanceEngine、PoseKit、SceneIntelligence、
                   PrivacyKit、EntitlementKit、StyleKit
```

**依赖规则**（不变量，执行计划任务须保持）：

- CameraCore 不导入 GuidanceEngine / SceneIntelligence / AccountKit / EntitlementKit（G4 快门独立的结构保证）。
- Features 依赖领域协议（SharedModels），App 装配具体实现；Capture 可订阅 AI 状态，但**快门命令直接调用 CameraCore**。
- 路由层取消 AI 不得取消已完成的照片持久化。
- L2 帧流水线：原始 sample buffer 不进 UI；低频 `GuidanceEvent`（文案/触觉）与有界 `OverlaySnapshot`（连续覆盖层）双路输出（技术大纲 §4）。

### 6.2 ppb-base（Go + Vue）

```
server-gateway/     camera 域 REST（/api/v1/camera/*）路由、匿名白名单、
                    gRPC 下传 x-ppb-subject 主体、代理 camera_registry
server-camera/      gRPC CameraService：ListTemplates（模板增量下发，已实现）；
                    分析/额度/登录 RPC（CAM-0001 未实现）；admin 面（部分已实现）；
                    domain 层任务/额度/主体模型；迁移与种子
base-manage-web/    管理后台底座（Liquid Glass）
  camera-manager-web/（ppb-camera 仓库）8 模块业务面插件：
    概览/模板/风格/AI策略/用户/反馈/成本/审计
```

**明确纠正**：代码**不在 ppb-chat 仓库**（历史文档口径已过时，见 [ADR-1101](../adr/调整记录.md) 与[实施现状](../implementation/实施现状与验证记录.md)）。服务端沿用 ppb-base 现有 MySQL/GORM 与网关模式，**不重建 React/Postgres 后台**——管理后台为 Vue（base-manage-web 底座 + camera-manager-web 插件）。

### 6.3 端云分工总表

| 职责 | 端侧 | 服务端（server-camera） | 后台（camera-manager-web） |
|---|---|---|---|
| 拍摄/裁切/存储/调色/导出 | 全部 | 无 | 无 |
| 构图辅助 L1 | 全部 | 无 | 无 |
| 主体/姿态检测 L2 | 全部（Vision） | 无 | 无 |
| 云分析 L3 | 触发/授权/抓帧/校验/ack | 任务受理、预留/核销/释放、推理调度 | — |
| 模板目录 | 缓存 + 内置兜底 | 版本化增量 + 下架墓碑 | 发布审核/下架 |
| 额度 | 只读缓存 | 唯一事实源（事务） | 补偿审批 |
| 账号 | 凭据（Keychain） | 匿名主体、绑定、token | 用户查询 |
| 审计/成本 | 无 | 日志与统计 | 查看/告警 |

## 7. 与质量门禁的对应

| 门禁 | 本架构落点 |
|---|---|
| G1 并发安全 | 检测/滤波/引导专用执行上下文；sample buffer 不进 UI；状态机时间可注入 |
| G2 性能 | §4 坐标映射单次几何源；预算表见技术大纲 §8（目标值，未实测不称达标） |
| G3 引导稳定 | §3.2 状态机 + 滞回 + 冷却；假达标禁止转移规则 |
| G4 快门独立 | §6.1 依赖规则；拍摄裁切在 App 层实现，CameraCore 无 AI 依赖 |
| G5 授权边界 | PrivacyKit 上传守卫；分析帧与反馈附件授权分离 |
