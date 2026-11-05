# ppb Go/GORM 常见坑（2026-10-27 camera 轮实测）

1. **GORM 零值 + `default` 标签 = 省略该列**：`Create` 时带 `default:x` 标签的零值字段不进 INSERT，由库默认顶替（如 `Status:0` 落库变 `2 published`、`Difficulty:0` 变 1）。写边界校验必须在上游做；直测 DDL CHECK 需显式列 raw INSERT。
2. **闭包不能引用自身所在短声明**：`err := f(func(){ err = ... })` 编译报 undefined（短声明 scope 始于语句结束）；闭包内用独立变量名。
3. **gorm check 标签**：`check:名字,条件`，条件内逗号安全（gorm 按首个逗号切名、余下重 join）；AutoMigrate 只在建表时落 CHECK，不向已存表回填。
4. **锁子句方言**：glebarez/sqlite 剥离 `FOR UPDATE/FOR SHARE`（驱动 ClauseBuilders 显式跳过）；gorm mysql 驱动把 `OnConflict{DoNothing}` 改写为 `ON DUPLICATE KEY UPDATE pk=pk`。跨方言锁协议在文件头显式写明，勿依赖"用了事务"。
5. **成功信封约定**：成功也要 `Base: errcode.BaseOf(nil)`（biz_code 空 + message "ok" + 200），对齐 server-file；错误信封文案保持通用防泄漏 DSN。
6. iOS 内置演示模板事实源：`ppb-camera/camera-ios-app/App/AppEnvironment.swift` BuiltInTemplateRepository 三目的（tpl_demo_portrait_half/portrait_half、tpl_demo_outfit_full/outfit_full、tpl_demo_travel/travel_checkin）；服务端 seed 同 ID/目的/名称。iOS Template 无 difficulty 字段。

## RPC 错误双轨（2026-10-29 集成轮实测）
server-iam 业务错误经 sentinelToStatus 以 **gRPC status error** 下发（message=`IAM-xxxx: 文案`，code 按 NotFound/AlreadyExists/FailedPrecondition/ResourceExhausted/InvalidArgument 语义）；BaseResp.biz_code 只在成功或个别面使用。消费方（rpcclient）必须 status.FromError 解析前缀归一，仅读 BaseResp 会把 NotFound 误判为传输失败（真实事故：邀请接受链 MANAGE-5000 误报）。注意 grpc.Code()→HTTP 建议值映射要消费侧自备。
