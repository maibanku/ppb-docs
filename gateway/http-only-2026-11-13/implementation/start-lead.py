#!/usr/bin/env python3
"""Launch one screen-backed Claude Lead with task-local context hooks."""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import uuid
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--work-dir', default='/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/gateway-http-only-20261113')
parser.add_argument('--dry-run', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
status = json.loads((root / 'progress/STATUS.json').read_text())
code = Path(status['code_root'])
work = Path(args.work_dir)
work.mkdir(parents=True, exist_ok=True)
claude = shutil.which('claude') or '/Users/pipi-ban/.nvm/versions/node/v24.21.0/bin/claude'
if not Path(claude).exists():
    raise SystemExit('Local Claude Code executable is unavailable')
metadata_path = work / 'lead-session.json'
if metadata_path.exists() and not args.dry_run:
    previous = json.loads(metadata_path.read_text())
    if previous.get('status') != 'launch_failed':
        raise SystemExit('A session was already launched. Inspect lead-session.json and claude agents --json before starting another writer.')
    archived = work / ('lead-session-failed-' + datetime.datetime.now().strftime('%H%M%S') + '.json')
    metadata_path.replace(archived)
hook = root / 'implementation/context-hook.py'
import shlex
command = shlex.join(['python3', str(hook)])
settings = {'enabledPlugins': {'claude-mem@thedotmack': False}, 'hooks': {
    'PreCompact': [{'hooks': [{'type': 'command', 'command': command + ' snapshot', 'timeout': 20}]}],
    'SessionStart': [{'matcher': 'startup|resume|compact|clear', 'hooks': [{'type': 'command', 'command': command + ' resume', 'timeout': 20}]}],
    'Stop': [{'hooks': [{'type': 'command', 'command': command + ' stop', 'timeout': 20}]}]
}}
settings_path = work / 'claude-task-settings.json'
settings_path.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + '\n')
settings_path.chmod(0o600)
session_id = str(uuid.uuid4())
prompt = f'''你是本次 ppb-gateway 全量 HTTP 透明网关改造的 Claude Lead。用户已授权你执行代码开发、调用 Claude subagents/team、使用本地 Docker、必要测试和分批提交推送。
先读取 {root / 'README.md'}、progress/CHECKPOINT.md、progress/STATUS.json 和 implementation/06-Claude-Lead执行与上下文.md，然后立即实施 P0 并继续 P1–P7，不能只给计划后结束。
最终网关只做 HTTP/WS 透明代理；当前已完成42条成员HTTP，剩105条gRPC、1本地聚合和19特殊入口必须全部按真实服务归属处理。不得将旧网关整体搬入泛业务access/BFF就宣称全量完成。服务端授权未等价补齐前不得删除原守卫。兼容现有URL、IAM浏览器回调、消息与通话、管理权限、文件流；保留真实数据库与MQ，不用运行时mock。
可按独占文件范围启动2–3个短subagents，Lead集成与提交；不要相互覆盖公共文件。每完成小批次先验证并提交推送，再更新进度与检查点继续。充分利用短任务及文件检查点，避免重复读全部仓库/完整历史/长日志。
本会话已配置1M自动压缩及PreCompact/SessionStart hooks。每个关键测试/提交后写短CHECKPOINT和STATUS，压缩后核对工作树再继续。真实API/认证/余额等阻塞如实记录，不能伪造通过。
现在开始读入口并执行，不等待额外确认。'''
argv = [claude, prompt, '--dangerously-skip-permissions', '--autocompact', '1M', '--name', 'ppb-gateway-http-only', '--session-id', session_id, '--settings', str(settings_path), '--add-dir', str(root.parents[1])]
env = os.environ.copy()
env.pop('CLAUDECODE', None)
env['PATH'] = '/Users/pipi-ban/sdk/go1.26.0/bin:/Users/pipi-ban/.nvm/versions/node/v24.21.0/bin:/Users/pipi-ban/.local/bin:' + env.get('PATH', '')
env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'
env.setdefault('TERM','xterm-256color')
socket_dir=work/'screen-socket';socket_dir.mkdir(exist_ok=True);socket_dir.chmod(0o700)
env['SCREENDIR']=str(socket_dir)
screen_log=work/'lead.screen.log';screen_log.touch(exist_ok=True);screen_log.chmod(0o600)
screen_config=work/'screenrc';screen_config.write_text('startup_message off\ndefscrollback 10000\nlogfile '+str(screen_log)+'\nlogfile flush 1\ndeflog on\n')
metadata = {'name': 'ppb-gateway-http-only', 'session_id': session_id, 'cwd': str(code), 'docs': str(root), 'autocompact': '1M', 'settings': str(settings_path), 'created_at': datetime.datetime.now().isoformat(), 'transport': 'screen', 'screen_dir': str(socket_dir), 'screen_log': str(screen_log), 'status': 'dry-run' if args.dry_run else 'launching', 'commands': {'list': 'SCREENDIR='+shlex.quote(str(socket_dir))+' /usr/bin/screen -ls', 'logs': 'tail -n 80 '+shlex.quote(str(screen_log)), 'attach': 'SCREENDIR='+shlex.quote(str(socket_dir))+' /usr/bin/screen -r ppb-gateway-http-only'}}
if args.dry_run:
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    raise SystemExit(0)
result = subprocess.run(['/usr/bin/screen','-c',str(screen_config),'-dmS','ppb-gateway-http-only',*argv], cwd=code, env=env, text=True, capture_output=True, timeout=20)
launch_log = work / 'launch.private.log'
launch_log.write_text(result.stdout + '\n' + result.stderr)
launch_log.chmod(0o600)
metadata['exit_code'] = result.returncode
metadata['status'] = 'launched' if result.returncode == 0 else 'launch_failed'
metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
metadata_path.chmod(0o600)
print(json.dumps({'status': metadata['status'], 'session_id': session_id, 'name': metadata['name'], 'metadata': str(metadata_path)}, ensure_ascii=False))
if result.returncode:
    raise SystemExit('Claude launch failed; inspect private launch log locally without exposing credentials.')
