# 实际删列与删除行为复核（2026-11-14）

## 已独立验证

- 当前代码基线：ppb-base `aff3dfd`；Claude 已完成最终二进制部署。
- 实际 MySQL 全部非系统 schema 扫描：后缀 biz_key、deleted_time 字段均 0；包括 ppb_iam、ppb_im、ppb_file、ppb_camera。此前剩余92个业务键列已实际删除。
- 实际 Camera SQLite `ppb-base/deploy/data/ppb_camera.db`：旧字段0。
- 后端六模块完整 Go 回归：65个测试包通过，命令退出0。
- 删除/撤回/解散/吊销/幂等专项回归：29项测试通过，0失败，无测试用例跳过（3个包没有匹配测试）。该组是进程内测试，不代替真实HTTP数据库验收。
- 网关配置从当前契约重新生成：145精确/模板路由，清除旧路径占位名与兼容别名；网关回归退出0。配置修改已通知Claude整合提交并重启加载。
- 五服务健康探针200；网关未登录删除会话返回401。
- 新接口验收工具已编译；244项入口的覆盖及契约漂移自检GREEN。这是工具自检，非244项业务全部通过。

## 尚未完成的验收

隔离环境中真实登录后，逐项执行创建→读回→删除→不可见→重复删除、越权删除、清理确认，以及文件、WS/语音视频相关完整链路。由仍运行的Claude Lead推进。旧142项契约清单的只读未登录探测不能作为本轮全量验收结论。

不得执行现有Docker栈的down -v或flushdb来准备测试，不得删除无关业务数据。私有备份、回退映射保持离线，不提交。

## 证据

工作目录：`/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/id-only-20261114/`

- `final-cutover-go.log`
- `deletion-regressions.jsonl`
- `gateway-final-routes-go.log`
- `post-cutover-health.json`
- `COORDINATION.md` 中的实际DDL、备份、部署交接记录

结论：数据库旧字段清理已完成；完整业务与全量接口验收尚未完成，不能宣称全部通过。
