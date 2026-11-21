# 目录结构迁移战役台账（2026-11-21，六仓并行）

依据：`ppb-docs/architecture/05-后端服务内部目录规范.md`。目标：六服务内部目录归位（transport/client/业务包/env），纯结构迁移零行为变更，全链验证跨服务调用。

## 预检事实（2026-11-21）

- 分支基线：ppb-iam@40edb17 / ppb-chat@efda1975 / ppb-file@ddd8732 / ppb-camera@2d2c87c / ppb-gateway@85d1466 / ppb-wardrobe@33e07cf（均 main）
- ppb-base main@fffc240 有**他人未提交**的 docs/*.md 删除——本战役不碰这些文件；deploy 改动单独 partial-stage
- camera 未跟踪文件 `StyleKit/.../T25...Tests 2.swift`（不碍事，保留）
- go1.26.0 @ $HOME/sdk/go1.26.0/bin；gateway GOWORK=off 基线构建 OK
- 跨仓引用：start-all.sh L410/414 引用 `$PPB_CAMERA_DIR/service-camera/config.yaml`（该文件本就不存在，服务容忍缺省——行为不变则不动）；iam main.go 错误文案引用旧模板路径（iam 代理同批改）；ppb-base/deploy/config/camera.yaml 含旧路径字样（收尾批核）
- 各仓 config/ 仅跟踪模板（gateway 另有跟踪的 config.yaml+gateway_config.go）；无本地未跟踪 config.yaml

## 波次

- W1（并行六代理）：file / iam / im / camera / gateway / wardrobe，各建 `feat/internal-dir-structure`，纯迁移+GOWORK=off build/vet/test 全绿+提交（不合 main 不推）
- W2（控制器）：ppb-base deploy 引用收口 + 跨服务调用验证（contracts 零改动核查、六仓构建复验、E2E start-all + verify-p2-manage）
- W3：验证全绿后各仓 ff-merge main（不推，推送等用户指令）；文档勾稽

## 台账

| 仓 | 代理 | BASE | 状态 | 提交区间 | 验证 |
| --- | --- | --- | --- | --- | --- |
| ppb-file | file-agent | ddd8732 | ✅ DONE 单提交 4643731（77 文件） | ddd8732..4643731 | build/vet/test 14 包绿（11 ok/3 no-test）；go.mod/sum 零 diff；试点链六环全通 |

### file 代理要点（W2 复核项）
- rehashObject 拆留 file/service；snowflake.go 随 file/model（避免 domain 沦单文件全局包）——deviations 已记
- 试点链 GetFileMetasByIds 六环核对全通（proto→注册→transport/file/file_meta_grpc→file/service→file/repo→ppb-chat 消费方仅依赖 contracts-file v0.1.1 零变化）
- residue：internal/httptunnel 原位（规范未列）；contracts-file 生成物注释旧路径（禁改生成物）
- MySQL 真机测试维持迁移前 skip 口径（无 PPB_FILE_MYSQL_DSN 即 skip，非本轮引入）
- 待 W2 核对：ppb-base regen-sqlite-snapshot.sh 是否硬编码 file 仓 config/ 路径（代理本机 grep 未命中）
- 报告：/tmp/dir-migration-2026-11-21/ppb-file-report.md
| ppb-iam | iam-agent | 40edb17 | ✅ DONE 4 提交 06cb4fc（基座模型/repo/service 拆分/入站+oidc+client+env） | 40edb17..06cb4fc | build/vet/test 20 包绿（含回环 e2e）；gofmt 0；go.mod/sum 零 diff；HTTP 42 路由+gRPC 29 方法名 diff 空；9 事务函数+signing_key 逐字一致 |

### iam 代理要点（W2 复核项）
- 4 项关键偏差已注理由：oauth_manage 留 platformadmin（接收者归属）、member_credentials 落 account（破环）、demo_seed 落 cmd/migrate（hashPassword 单一出口）、DeliverySender 端口归 notify（破测试环）
- 跨包未导出助手按归属上移导出（shared.HMACDigest/audit.BuildAudit 等 5 处）+1 只读观测方法 AccountService.DeliveryState()（smtp 白盒测试用）——API 面微增，已记录
- 后续批次：AccountRepo 大接口收窄、credential 服务层上移
- 报告：/tmp/dir-migration-2026-11-21/ppb-iam-report.md（118 条 rename 映射）
| ppb-chat | im-agent | efda1975 | ✅ DONE 4 提交 250e2d3a（113 文件 +311/−274） | efda1975..250e2d3a | build/vet/test 20 包绿；go.mod/sum 零 diff |

### im 代理要点（W2 复核项）
- call 因 repo 本轮冻结落 internal/call/service（包名不变调用点零改动），模型/仓储批次展平（D-1）
- 旧 grpcUserClient 全仓零调用方（生产=NewLocalUserClient，grep 证据在报告）——保留迁 client/grpc/im/org_compat_grpc.go，退役另批
- 门面 internal/service/service.go + 11 白盒测试原位（residue R-1）；domain/repo 待迁清单 R-2/R-3（下批）
- refaccess 拆包后 baseOf 信封助手逐字复制（D-2）；MemberIDCache 驻 client 根（D-3）
- gofmt 33 文件 BASE 既有债未动（D-7）
- 报告：/tmp/dir-migration-2026-11-21/ppb-chat-report.md
| ppb-camera | camera-agent | 2d2c87c | ✅ DONE 4 提交 ae41ca3（platform/db→能力域→transport→env） | 2d2c87c..ae41ca3 | build/vet/test 23 包绿（14 ok/9 no-test，文件集合与迁移前一致）；go.mod/sum 零 diff；禁动目录零触碰 |

### camera 代理要点（W2 复核项）
- 三处混载文件按符号拆（camera_migrate outbox/游标助手、model.go 实体、全域锁上收 platform/db）——未导出跨包 helper 不拆编译不过，单一实现零复制（已认可，同 R2 口径）
- quota 结算事务六助手在 quota/repo 导出供 task/subject repo 同事务调用（§1.1.5 事务完整性）——仅可见性变化
- 两测试包转外部包避 testkit import 环（dbmigrate、quota repo）
- 根 config.yaml 原位保留（start-all 消费；切 env/ 属 CFG-3 另批）；模板已迁 env/——W2 核对 camera env/ 与 config/ 现势
- 第 4 提交曾误带未跟踪 iOS 文件已 amend 剔除
- 报告：/tmp/dir-migration-2026-11-21/ppb-camera-report.md
| ppb-gateway | gateway-agent | 85d1466 | ✅ DONE 85d1466..9bdf7de 单提交 | 85d1466..9bdf7de | build/vet/test 4 包绿；go.mod/sum 零 diff |

### gateway 代理要点（W2 复核项）
- transparent_main 按符号拆：runTransparent 留根 boot_wire（避 import 环），其余入 internal/proxy
- static/ 随迁 internal/proxy/static/（go:embed 相对路径强制）——W2 复核 start-all/Dockerfile 对 service-gateway/static 的外部引用
- 四导出符号改名（main→proxy 跨包所需；gateway 无外部 importer，风险可控）
- 根 BASE 即有 6 文件非 gofmt——未顺手格式化（保纯迁移），W2 不追
- 报告：/tmp/dir-migration-2026-11-21/ppb-gateway-report.md
| ppb-wardrobe | wardrobe-agent | 33e07cf | ✅ DONE 单提交 d2e6aa4（16 文件 +425/−308，14 rename） | 33e07cf..d2e6aa4 | build/vet/test 绿；34 路由逐条 diff 同；go.mod/sum 零改动 |

### wardrobe 代理要点（W2 复核项）
- api 解散→transport 五域子包（tasks/assets/auth/models/vton）+ 根包（sync/export/audit/access_grants/server）；同接收者拆包必然引入每域 Handler + transport/core——机械等价改写，黑盒契约套件实证无行为变化（已认可，Ruling 见下）
- server.go 留 transport 根包（测试需可导入 New(Deps)）；access_grants 留根包（support 管理面归属）
- 提交尾注为 Claude Sonnet 5（执行模型即 sonnet，署名如实，不改）
- 报告：/tmp/dir-migration-2026-11-21/ppb-wardrobe-report.md

## W2/W3 结果（2026-11-21 收口）

**W2 验证证据**：
- 六仓 git 级复验：提交数 iam4/im4/file1/camera4/gateway1/wardrobe1；`go.mod`/`go.sum` 对 BASE diff 全空；contracts-* 与仓顶层 api/ api/policies 全空（跨服务契约面零触碰）
- ppb-base 工具收口：`tools/gen_error_codes.py` 扫描路径更正（errcode→go-framework/errcode、imdef→internal/imdef、file→internal/file/service、gateway→internal/proxy；todo 无目录维持静默跳过）——路径解析冒烟 OK；产物 docs/api/error-codes.md 从未跟踪且 docs/ 正被并行会话清理，**再生成暂缓**
- endpoint-audit inventory/native_*.go 引用旧路径（含行号锚）——属该验收 lane 自身再生成流程，**跟进项不阻塞本役**
- E2E：stop-all → start-all（MySQL 模式，db.env）**6/6 健康**（im9112/file9114/iam9117/camera9116/gateway8080，全部自迁移后分支构建）；im/iam MySQL 迁移 OK、platform registry 种子零漂移；网关路由 **130 条同迁移前口径**；api-policies 四域聚合 OK
- verify-p2-manage：首轮 PASS=5 FAIL=1（qa-tokens）——定性为**调用环境伪象**（start-all 自举 go PATH 而 verify 脚本无；`go run` command-not-found 被 2>/dev/null 吞）；带 PATH 复跑 **PASS=14 FAIL=0**（含 qatokens 签发、网关→IM 前转、member/manage 链路、负控 401/403/MANAGE-0004、forged-actor 无 5xx）
- 追加定性证据：qatokens 五参手动复跑成功（迁移后 iam 内部 RPC IssueMemberSession + 签发链正常）

**W3 收口**：
- 六仓 `main` ff-merge：iam→06cb4fc / im→250e2d3a / file→4643731 / camera→ae41ca3 / gateway→9bdf7de / wardrobe→d2e6aa4；feat 分支删除
- ppb-base 仅 partial-stage 提交 tools/gen_error_codes.py（并行会话的 21 条 docs 删除与 .claude/wt-policies/ 不碰）
- E2E 栈保持运行（pid 在 deploy/run/）

**推送（用户授权"开发完成直接推送"）**：八仓 `git push origin main` 全部成功且 ls-remote 实证一致——iam@06cb4fc / chat@250e2d3a / file@4643731 / camera@ae41ca3 / gateway@9bdf7de / wardrobe@d2e6aa4 / base@d196611 / docs@46c6159。

**推送后全量测试（main 状态）**：
- 六套并行首轮：camera 15 ok / file 11 ok / gateway 4 ok / iam 20 ok / wardrobe 5 ok 全绿；im 19 ok/3 FAIL（TestCoalesceSecondWindow 合流窗口计时测试）
- im 失败定性：**六套并行抢 CPU 的计时抖动，非回归**——串行复跑 `go test -count=1 ./...` **exit=0 ok=20 FAIL=0**（realtime/ws 转绿）
- 注：/tmp 下 test-p456.log 等为各代理自身早期测试日志，与本轮无关

## Rulings（补）

## W2 ppb-base 收口清单（全部代理回报后执行）

1. `tools/gen_error_codes.py:25-27` 硬编码扫描路径：FILE 段 `service-file/internal/service`→`service-file/internal/file/service`；IM 段 `service-im/internal/service/imdef`→`service-im/internal/imdef`（im 报告§32 行）；`service-im/internal/service/todo` 在现树无此目录（陈旧死路径，先例在案——改时一并处理或注记）；GATEWAY 根路径递归覆盖可不动——改后实跑一次自证
2. `tools/endpoint-audit/inventory.json` 大量 `source` 旧路径（file/iam handler）：查 endpoint-audit 工具的再生成方式，可再生成则跑，否则机械串替换旧→新路径
3. `deploy/scripts/regen-sqlite-snapshot.sh` 引用 `$ROOT/config/*.snapshot.yaml`（deploy 侧生成物）与已退役 `bin/user.exe`——先例陈旧，与本次迁移无关，只记录不动
4. Dockerfile per-service 引用已删 server-pkg：P8 债务在案，不动
5. 六仓复验：go.mod/go.sum 零 diff、contracts-* 零触碰、GOWORK=off build/test 抽查
6. E2E：stop-all → start-all（MySQL 模式）→ verify-p2-manage

## Rulings

- R1（gateway）：transparent_main 按符号拆、runTransparent 留根装配、static/ 随 embed 迁 internal/proxy/static/、四导出符号因跨包改名——均为 Go 包机制所需的最小改写；gateway 无外部 importer，接受。
- R2（wardrobe）：单一 *Server 接收者拆五域子包必然引入每域 Handler+transport/core 共享件——超出"仅 import 改写"字面但属机械等价；以 34 路由逐条 diff 全同 + 黑盒契约套件绿实证，接受。同款情况预计也适用于其他仓同接收者拆包。
- R3（wardrobe）：提交尾注 Claude Sonnet 5 与任务书模板（Opus 5）不一致——执行模型即 Sonnet，署名如实，不改；后续代理同理按实际模型署名即可。
