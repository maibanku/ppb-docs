#!/usr/bin/env python3
"""Task-local Claude hooks: preserve bounded state, never read credentials/transcripts."""
import csv
import datetime
import json
import subprocess
import sys
from pathlib import Path
from zoneinfo import ZoneInfo

root = Path(__file__).resolve().parent.parent
progress = root / 'progress'
try:
    event = json.load(sys.stdin)
except (ValueError, EOFError):
    event = {}
status_path = progress / 'STATUS.json'
status = json.loads(status_path.read_text()) if status_path.exists() else {}
code = Path(status.get('code_root', '/Users/pipi-ban/Desktop/code/vscode/ppb-base'))

def git(*args):
    result = subprocess.run(['git', '-C', str(code), *args], capture_output=True, text=True, timeout=10)
    return result.stdout[:6000] if result.returncode == 0 else '(git inspection unavailable)'

def snapshot():
    progress.mkdir(parents=True, exist_ok=True)
    text = '# 自动运行快照（不能替代语义检查点）\n\n'
    text += '时间：' + datetime.datetime.now(ZoneInfo('Asia/Shanghai')).isoformat() + '\n'
    text += '事件：' + str(event.get('hook_event_name', 'manual')) + '\n'
    text += '会话：' + str(event.get('session_id', 'hook-test'))[:80] + '\n'
    text += '当前批次：' + str(status.get('current_phase', 'P0')) + '\n\n'
    text += 'HEAD：' + git('rev-parse', '--short', 'HEAD') + '\n'
    text += '工作树（仅路径）：\n```text\n' + git('status', '--short') + '\n```\n'
    text += '改动统计：\n```text\n' + git('diff', '--stat') + '\n```\n'
    text += '\n继续时读取 CHECKPOINT.md、STATUS.json，核对实际文件后继续，不重做全部探索。\n'
    dest = progress / 'RUNTIME-CHECKPOINT.md'
    temporary = dest.with_suffix('.tmp')
    temporary.write_text(text)
    temporary.replace(dest)

mode = sys.argv[1] if len(sys.argv) > 1 else 'snapshot'
if mode == 'resume':
    checkpoint = progress / 'CHECKPOINT.md'
    print('本次任务：HTTP-only gateway 全量改造。先恢复状态，禁止把旧网关搬到泛业务 BFF 后宣称完成。')
    print('执行入口：' + str(root / 'README.md'))
    print('状态文件：' + str(status_path))
    print('语义检查点：' + str(checkpoint))
    if checkpoint.exists():
        print(checkpoint.read_text()[:5000])
    print('当前窗口使用 --autocompact 1M；每个批次后更新检查点，长日志只写本地文件。')
elif mode == 'stop':
    snapshot()
    # One continuation reminder only; respect real blockers and avoid an endless hook loop.
    if event.get('stop_hook_active'):
        sys.exit(0)
    if status.get('state') == 'blocked' and status.get('blockers'):
        sys.exit(0)
    done = status.get('state') == 'complete'
    report = progress / 'FINAL-ACCEPTANCE.md'
    matrix = progress / 'ROUTE-STATUS.csv'
    verified = False
    if matrix.exists():
        with matrix.open(newline='') as handle:
            rows = list(csv.DictReader(handle))
        verified = len(rows) >= 148 and all(r.get('status') == 'verified' for r in rows)
    if not (done and report.exists() and verified):
        print(json.dumps({'decision': 'block', 'reason': '全量任务尚无完整验收。先更新 CHECKPOINT/STATUS/逐入口矩阵，继续当前未完成批次；不得只交付计划、首批或泛业务 BFF。真实外部阻塞须如实记录，不要虚标 complete。'}, ensure_ascii=False))
else:
    snapshot()
