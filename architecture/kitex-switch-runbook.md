# Kitex 切换 runbook（旧 gRPC 二进制 → Kitex 全量）

> 日期：2026-11-23 · 已执行一次（本机 dev 布局），记录口径供复现
> 前置：四服务源码已在 main（Kitex 版）；etcd 常驻 127.0.0.1:2379（infra 二进制）；
> deploy/config/*.yaml 带 registry.etcd 段且过各服务 deploy 兼容门禁。

## 切换机制：start-all.sh 即切换器（无需手工换 bin）

`deploy/scripts/start-all.sh` 从兄弟仓源码构建到 `deploy/bin/`，并以
「健康进程的二进制 mtime 晚于进程启动时间」判定旧进程 → 自动 kill + 换新重启。
源码切 Kitex 后重跑即完成切换——**不存在手工替换二进制的步骤**。

```bash
cd ppb-base/deploy
export PATH=$HOME/sdk/go1.26.0/bin:/opt/homebrew/bin:$PATH
bash scripts/start-all.sh        # APP_ENV 缺省 dev（db.env 供凭据）
```

输出确认点（2026-11-23 实跑）：
- `im 旧二进制（…比进程新）— 换新重启` / `file 旧二进制 … 换新重启`
- `[6/6] 全部服务健康`（im 9112 /healthz、file 9114 /ping、iam 9117 /ping、camera 9116 /healthz、gateway 8080 /ping）

## 切换后验收（四步）

```bash
# 1. etcd 四键（Kitex 注册，标准口）
ETCDCTL_API=3 etcdctl --endpoints=127.0.0.1:2379 get --prefix "kitex/registry-etcd/" --keys-only
#   预期：ppbchat-{im:9102, file:9104, camera:9106, iam:9107}

# 2. 网关链路（HTTP 反代不变）
curl http://192.168.3.55:8080/ping
curl http://192.168.3.55:8080/api/v1/camera/templates   # 空库则 revision "0"，成功信封即可

# 3. 服务日志确认 Kitex 监听（各 logs/<svc>.log）
grep "kitex" logs/im.log   # 「server-im kitex listening :9102」类

# 4. 停止/排障
bash scripts/stop-all.sh   # pid 文件在 run/，日志在 logs/
```

## 口径注记

- gateway 不迁移（HTTP 反代设计决策，136 路由）——它调各服务走 HTTP 面，无感切换。
- camera 用仓内 `service-camera/config.yaml`（SQLite 起步态）；模板数据经
  `PPB_CAMERA_SEED_TEMPLATES=1` 种子（按需）。
- iam 若以非 pidfile 方式常驻（如手工起），start-all 检测「健康但 pid 定位失败」
  会保守跳过不重启——手工实例需自行重启换新。
- 旧 `deploy/bin/*.kitex` 过渡副本已删除（staging 使命完成，bin/ 内即为源码构建产物）。
- 回退：`git revert` 服务仓到迁移前提交后重跑 start-all.sh（同一机制反向生效）。
