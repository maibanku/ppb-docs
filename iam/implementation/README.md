# 本地 Claude Code 实施入口

本入口负责完整下载四仓、准备功能分支并启动本机Claude Code。项目功能由[实施提示词](CLAUDE_CODE_PROMPT.md)驱动编码，脚本本身不声称完成IAM。

## 1. 同级工作目录

```text
ppb-workspace/
  ppb-docs/
  ppb-base/
  ppb-chat/
  ppb-camera/
```

同级关系是chat/camera管理插件的`file:../../ppb-base/base-manage-web`依赖所需。实际服务目录是ppb-base/server-user，目标新增server-iam；后台底座也在ppb-base。

## 2. 本机前置条件

Python 3.9+、Git、能够访问私有仓库的本机Git凭据或已认证GitHub CLI。Claude Code已安装且可在终端运行。Go/Node/Rust/C++/Swift工具链在Claude阶段0按各仓配置核验；iOS完整构建需要macOS/Xcode。

安装与认证按[Claude Code官方说明](https://code.claude.com/docs/en/setup)。脚本不安装软件、不读取或打印Key、不改写现有Claude/智谱配置，也不自动绕过权限。交互式acceptEdits仍可能要求命令许可，这是Claude Code权限机制。

## 3. 下载后立即执行

在选定的父目录先取得文档仓库；已有仓库用正常Git流程更新，不覆盖未提交修改：

```bash
git clone https://github.com/maibanku/ppb-docs.git
python3 ppb-docs/iam/implementation/bootstrap.py --root .
```

Windows PowerShell可用：

```powershell
git clone https://github.com/maibanku/ppb-docs.git
py -3 ppb-docs/iam/implementation/bootstrap.py --root .
```

脚本依次下载缺少的仓库，检查origin及工作区，再在四仓创建/切换`feat/iam-v0.4`：优先本地已有分支，其次远程同名分支，否则从origin/main创建。不会重置已有实现，不拉取合并到已有功能分支，不向main提交。

准备完毕后自动启动Claude Code，加载完整提示词，要求先提交阶段0，再持续编码、检查、逐步提交；每个可运行阶段通过后推送各仓功能分支。网络/认证失败保留本地提交并如实记录。

只下载和建分支，不调用模型：

```bash
python3 ppb-docs/iam/implementation/bootstrap.py --root . --prepare-only
```

只读检查：

```bash
python3 ppb-docs/iam/implementation/bootstrap.py --root . --check-only
```

若已存在目录有未提交修改，脚本拒绝切换，不会stash/reset/clean；先保留并处理，或换全新父目录。中断重试沿用已有仓库与分支，已完成代码必须先按提示词提交。

## 4. 边写边提交

四仓统一使用feat/iam-v0.4，人员只维护该功能分支。每完成一个可验证小步骤提交具体文件；阶段检查通过后正常push，禁止强推/直接合并main。progress.md记录跨仓配套SHA、测试和下一步，不把所有变更攒到最终一次提交。

这份提示词准备提交本身在文档main发布，方便首次clone取得；实际功能实施及后续文档修改进入功能分支。初始提示词提交不代表代码仓已实施。

## 5. 智谱与执行范围

沿用本机已配置的模型供应商。若使用智谱兼容接入，按智谱官方支持的方式预先在本机配置，脚本不猜测端点/模型或收费规则。不要把Key发到聊天、提示词、代码或Git。Claude实际走哪个供应商及消耗额度应以本机配置与供应商账单确认。

ChatGPT会话不能通过这段脚本控制用户物理电脑；用户需要在本机运行入口。没有Claude命令、认证或Git私库权限时，脚本报出阻塞并保留准备结果，不声称已执行IAM编码。

## 6. 参考与验证

命令依据：[Claude CLI reference](https://code.claude.com/docs/en/cli-reference)，使用`--add-dir`、`--append-system-prompt-file`、`--permission-mode acceptEdits`。脚本先检查本机帮助确认支持，不使用危险跳过权限参数。

本机运行单元测试：`python3 -m unittest discover -s ppb-docs/iam/implementation/tests -v`。测试不调用模型、不访问真实远端、不修改用户仓库；测试报告不等于实际四仓下载或IAM功能完成。
