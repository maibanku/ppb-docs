# ppb-camera · AI 构图代码分析与实施差距

日期：2026-11-02。方法：GitHub 固定提交的源码静态分析；未运行 App、Swift 测试、Web 构建、真机或抓包。源码存在不等于运行通过，测试文件存在不等于功能已验收。

## 1. 分析基线与范围

- 代码：[ppb-camera@b3b7dad](https://github.com/maibanku/ppb-camera/commit/b3b7dadf82829631056eb28b98b8980df510362c)，main，提交说明为 analysis regions / exposure / arc zoom controls。
- 原文档：[ppb-docs@200994a](https://github.com/maibanku/ppb-docs/commit/200994ab8beb8c95bd3def0082e6d1e372ce72e1)，main。
- 读取范围：iOS App 装配、拍摄页、CameraCore、13 个 Package 的实现入口/相关模型、模板客户端、存储与账号实现、代表性测试、Web API 与策略页面；结合 camera 当前 FS/技术/ADR。
- 未核验范围：本机 Mac 工作树、其他分支、ppb-base 的实际服务端源码、生产环境、真实供应商。服务端栈/接口现状引用已有文档时标为文档依据，不把它升级为本轮源码事实。
- 两仓库递归文件列表未发现 AGENTS.md/CLAUDE.md；本次只修改 ppb-docs/camera 文档，不修改 ppb-camera 应用代码。

配套：[增量需求 FS-14](../pr/FS-14-AI构图分析与实时引导.md) · [实现技术设计](../tech/AI构图实现技术设计.md) · [专项验收](../ac/AI构图专项验收.md)。

## 2. 主要结论

当前“构图”是 **本地 ROI 选择和图片提取**，不是 AI 构图识别。实际路径为：按钮进入选区 → 拖动/缩放 → 读取选区 → 调用 capturePhoto → 解码/方向归一/裁切 → 内存缩略图；文案明确“未进行AI分析”。

没有发现接入相机的连续分析帧流、Vision 人体检测、Core Motion 构图测量、GuidanceEngine 实时状态机或真实云分析请求。相关包目前是职责注释和 PackageInfo，占位测试仅校验包名。

当前代码的全屏预览与保存原片**允许视野不同**，这符合最新 FS-12/13。不能沿用先前讨论中的“默认按屏幕裁切成片”，也不能因旧 WYSIWYG helper 与测试仍在就断言普通快门在自动裁切。

## 3. 已有能力与证据

下表路径均位于 ppb-camera；行号以固定提交为准，后续可能移动。

| 能力 | 源码证据 | 本轮结论 |
| --- | --- | --- |
| 原生 iOS 工程 | camera-ios-app/project.yml：iOS 17、Swift 6、strict concurrency、XcodeGen | 可按现有工程增量实现，不新建另一套 App |
| 全屏预览 | CameraCore/CameraPreviewView.swift；Features/Capture/CaptureView.swift | 系统预览层 resizeAspectFill，控件悬浮 |
| 普通快门 | CaptureView.swift:946 起 capture()；CameraCore/AVCameraSource.swift:112 起 capturePhoto() | 原片直接送 PhotoStore，无自动 3:4 裁切，无 AI/账号/额度前置 |
| ROI 提取 | CaptureView.swift:477 readROISelection、1313 ROIGeometry、1444 ROIExtractionModel、1488 ROISnapshotCrop | 真拍后临时裁切，不存作品、不上传、不生成分析结论 |
| 迟到成功隔离 | ROIExtractionModel.begin/invalidate/accept | generation 不符拒绝接受，适合作为未来 revision 机制的起点 |
| 曝光、数字变焦 | AVCameraSource 中 exposureBias / zoom API；ExposureBias.swift、ZoomModel.swift | 有硬件调用与范围校验；实际响应、时序和画质未真机验证 |
| 模板本地使用 | App/AppEnvironment.swift 的 BuiltInTemplateRepository | 三个内置演示模板；不冒充网络模板 |
| 模板网络客户端 | NetworkKit/TemplateCatalogClient.swift、Models、Transport | 已有真实 GET /api/v1/camera/templates 客户端和解码/重试；不是纯 marker |
| 模板接线 | AppEnvironment.templateRepository 为 BuiltInTemplateRepository；project.yml 依赖列表无 NetworkKit | 客户端实现存在，但 App 未见远端目录接线；不能宣称模板端到端完成 |
| 照片存储 | StorageKit/PhotoStore.swift | actor、原片/元数据/索引、原子写入和 recover 路径；不是已验证的 SwiftData 数据库 |
| IAM | AccountKit 实现、AppEnvironment 与 IAMAccountSection | OIDC/PKCE/Keychain 等源码存在；本轮未联调，基础拍摄未加账号门槛 |
| Web API | camera-manager-web/src/api/*.ts、package.json | Vue 3 + Element Plus + base-manage-web；有真实 http 调用，不能统一称为“纯前端 stub” |
| Web 策略页 | src/api/strategies.ts、views/strategies/StrategiesView.vue | 请求 /manage/camera/strategies，仍展示 not_provisioned 域未建空态，非策略编辑发布系统 |

链接示例：[CaptureView](https://github.com/maibanku/ppb-camera/blob/b3b7dadf82829631056eb28b98b8980df510362c/camera-ios-app/Features/Capture/CaptureView.swift)、[CameraApp](https://github.com/maibanku/ppb-camera/blob/b3b7dadf82829631056eb28b98b8980df510362c/camera-ios-app/App/CameraApp.swift)、[AVCameraSource](https://github.com/maibanku/ppb-camera/blob/b3b7dadf82829631056eb28b98b8980df510362c/camera-ios-app/Packages/CameraCore/Sources/CameraCore/AVCameraSource.swift)。

## 4. 未实现与文档差距

| 项目 | 源码事实 | 文档/目标 | 处理 |
| --- | --- | --- | --- |
| 导航 | CameraApp.AppTab 只有 capture/inspire/gallery；测试断言三 Tab | ADR-1101 要求拍照/灵感/作品/我的四 Tab | 保留四 Tab 为目标，明确待实现；不把源码三 Tab 改写成新需求 |
| AI 包 | PoseKit/GuidanceEngine/SceneIntelligence/PrivacyKit/EntitlementKit 只有 PackageInfo | 职责注释写有 Vision、滞回、云任务等 | 注释是计划，不是实现；按 FS-14 分层开发 |
| 分析帧 | AVCameraSource 只配置照片输出；未见 AVCaptureVideoDataOutput 接线 | L2 连续检测 | 新增独立分析能力，不让快门协议依赖 AI |
| L2 装配 | project.yml/pbxproj 未见 AI 相关包作为 App 依赖 | 包目录已创建 | 实现包后显式接入工程，不能只提交目录 |
| 保存范围 | 普通快门直接保存完整原片 | 产品功能设计、旧架构仍写默认 WYSIWYG 3:4 | 以 FS-12/13 为准，本轮加迁移提示与技术口径 |
| 原实现记录 | 旧实施记录引用 ff652ee 工作树、NetworkKit marker、API stub | 当前提交已变化 | 保留历史，新增本报告作为更新基线，不把历史测试当本轮结果 |
| 性能 | 无真机测量 | 15fps、16ms、3s 等目标 | 保持目标属性；预研失败时正式修订门槛，不伪报通过 |

测试定位：[SessionAndStartupTests](https://github.com/maibanku/ppb-camera/blob/b3b7dadf82829631056eb28b98b8980df510362c/camera-ios-app/Tests/CameraAppTests/SessionAndStartupTests.swift) 的三 Tab 测试、ROI 几何/代数测试以及旧 WYSIWYG helper 测试均存在。GuidanceEngineTests 仅测试 PackageInfo.name 非空，不能覆盖引导逻辑。

## 5. 需要优先验证的实现风险

以下为源码可定位风险，不宣称已经在真机复现。

| 风险 | 证据与推断 | 建议处理与验证 |
| --- | --- | --- |
| 迟到失败仍显示 toast | readROISelection 的普通 catch 调用 finishFailure 后没有检查 Bool，随后总显示“读取选区失败” | 使用返回值和当前会话双重守卫；旧任务失败不能干扰新一轮；增加调用侧测试 |
| 大图处理可能卡 UI | readROISelection Task 标注 MainActor，ROISnapshotCrop.makeSnapshot 也在 MainActor 同步解码、归一和裁切 | 图像计算放专用执行上下文，回 UI 只传安全值；测大照片耗时和峰值内存 |
| ROI 读取与快门竞争 | 两路都调用同一 capturePhoto；UI 不阻塞快门不代表底层没有相机资源竞争 | 真机并发压力测试；L2 改用视频分析帧，读取选区保留显式快照语义；硬件忙如实反馈 |
| 曝光读回时序 | setExposureTargetBias 使用 nil completion，紧接着读 exposureTargetBias | SDK 完成时机与最终应用值需实测；必要时用完成回调/稳定确认，generation 防止旧结果回填 |
| 前摄镜像与视野 | 代码用“预览镜像、原片不镜像”假设；产品已标未实机验证 | 对实际连接镜像与方向做快照校准；多镜头/倍率分别校验 |
| 旧 helper 注释/测试误导 | WYSIWYMCaptureCrop 保留但 capture() 不调用 | 标记 legacy；不要让 helper 单测代替保存链路集成测试 |

## 6. 推荐开发顺序

1. 固定基线与文档口径：原片保存、ROI 分析输入、四 Tab 目标和三 Tab 实况分开。
2. 修 ROI 迟到失败守卫，验证曝光完成与 UI 大图处理风险；不为 AI 改写 PhotoStore。
3. CameraCore 新增有界 AnalysisFrameSource；帧上下文含方向、镜像、zoom 与 ROI revision；先验证映射。
4. PoseKit 实现检测/置信度/主体关联；GuidanceEngine 实现纯规则、注入单调时间、滞回和双路输出。
5. App 装配真实 L2，明确启动/关闭/降级；保留现有 ROI 读取功能，不偷换成上传按钮。
6. NetworkKit 模板接线与云任务分别推进；L3 复用 ready→ack→committed 规则，不能“结果生成即扣费”。
7. PrivacyKit、SceneIntelligence、EntitlementKit 和 ppb-base 协议核对后才接云端；后台由空态扩展为真实管理闭环。
8. 逐层执行专项验收、真机和隐私验证，未通过不得展示已识别/已达标/云分析成功。

## 7. 本轮验证声明

已完成：固定 SHA 读取、源码路径与符号交叉核对、代表性测试内容阅读、文档相对链接/结构校验（结果以本轮交付记录为准）。未完成：任何 Swift/iOS/Web/Go 构建或运行测试、真机性能、摄像头镜像和硬件曝光时序。当前云端执行环境未提供 Xcode/iOS 真机，不能据此出具软件发布通过结论。
