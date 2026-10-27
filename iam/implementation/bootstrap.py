#!/usr/bin/env python3
"""Clone PPB siblings, prepare feature branches, then start local Claude Code.

No provider configuration, stored credentials, forced updates, or production actions.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPOSITORIES = ('ppb-docs', 'ppb-base', 'ppb-chat', 'ppb-camera')
DEFAULT_BRANCH = 'feat/iam-v0.4'


class SetupError(Exception):
    pass


def run(args, cwd=None, capture=False, check=True):
    result = subprocess.run(
        [str(x) for x in args], cwd=cwd, text=True, encoding='utf-8',
        errors='replace', stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None, check=False,
    )
    if check and result.returncode:
        # Avoid repeating credential-helper output or URLs that may contain secrets.
        raise SetupError(f'命令失败（退出码 {result.returncode}）：{Path(str(args[0])).name} {args[1] if len(args)>1 else ""}；请检查终端输出与本机认证。')
    return result


def git(repo, *args, check=True):
    return run(['git', '-C', repo, *args], capture=True, check=check)


def validate_repository(repo, expected_name):
    if repo.is_symlink():
        raise SetupError(f'{repo} 是符号链接；请指定独立父目录。')
    if not repo.is_dir() or git(repo, 'rev-parse', '--show-toplevel', check=False).returncode:
        raise SetupError(f'{repo} 已存在但不是Git仓库，未覆盖。')
    top = Path(git(repo, 'rev-parse', '--show-toplevel').stdout.strip()).resolve()
    if top != repo.resolve():
        raise SetupError(f'{repo} 不是独立仓库根目录。')
    remote = git(repo, 'remote', 'get-url', 'origin').stdout.strip().rstrip('/')
    suffix = f'maibanku/{expected_name}'
    valid = {f'https://github.com/{suffix}', f'https://github.com/{suffix}.git',
             f'git@github.com:{suffix}', f'git@github.com:{suffix}.git',
             f'ssh://git@github.com/{suffix}', f'ssh://git@github.com/{suffix}.git'}
    if remote not in valid:
        raise SetupError(f'{expected_name} 的origin不是预期GitHub仓库，未改写。')
    if git(repo, 'status', '--porcelain', '--untracked-files=normal').stdout.strip():
        raise SetupError(f'{expected_name} 有未提交/未跟踪修改；请先保留并处理，或使用新的父目录。脚本不stash/reset/clean。')
    if not git(repo, 'rev-parse', '--verify', 'HEAD', check=False).returncode == 0:
        raise SetupError(f'{expected_name} 没有可用HEAD。')


def prepare_branch(repo, branch):
    git(repo, 'fetch', 'origin')
    if git(repo, 'show-ref', '--verify', '--quiet', f'refs/heads/{branch}', check=False).returncode == 0:
        git(repo, 'switch', branch)
        # Preserve local commits. Do not merge/reset an existing implementation branch.
    elif git(repo, 'show-ref', '--verify', '--quiet', f'refs/remotes/origin/{branch}', check=False).returncode == 0:
        git(repo, 'switch', '--track', '-c', branch, f'origin/{branch}')
    else:
        git(repo, 'rev-parse', '--verify', 'origin/main')
        git(repo, 'switch', '-c', branch, 'origin/main')
    current = git(repo, 'branch', '--show-current').stdout.strip()
    if current != branch:
        raise SetupError(f'{repo.name} 未进入目标分支。')
    return {'branch': current, 'commit': git(repo, 'rev-parse', 'HEAD').stdout.strip()}


def launch(root, prompt, branch):
    claude = shutil.which('claude')
    if not claude:
        raise SetupError('四仓准备后检测不到claude命令。请按官方说明安装/认证，再运行同一命令；脚本不安装或改写模型配置。')
    version = run([claude, '--version'], capture=True)
    print('Claude Code: ' + version.stdout.strip(), flush=True)
    help_text = run([claude, '--help'], capture=True).stdout
    for flag in ('--append-system-prompt-file', '--add-dir', '--permission-mode'):
        if flag not in help_text:
            raise SetupError(f'本机Claude Code不支持{flag}，请按官方说明更新。')
    message = f'开始执行附加的PPB IAM实施提示词。四个仓库必须使用{branch}；每个可验证步骤立即提交，阶段通过后推送功能分支。先检查规则与基线、提交阶段0，然后实际编码，不停留在计划。'
    args = [claude, '--permission-mode', 'acceptEdits',
            '--append-system-prompt-file', str(prompt)]
    # Parent cwd already scopes all four repos; explicit grants clarify multi-repo access.
    for name in REPOSITORIES:
        args += ['--add-dir', str(root / name)]
    args.append(message)
    print('启动本机Claude Code；沿用已有认证/模型供应商配置。', flush=True)
    return run(args, cwd=root, check=False).returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3],
                        help='四仓共同父目录，默认当前ppb-docs的父目录')
    parser.add_argument('--branch', default=DEFAULT_BRANCH)
    parser.add_argument('--prepare-only', action='store_true', help='只下载并准备分支，不启动模型')
    parser.add_argument('--check-only', action='store_true', help='只检查现有目录/工具，不下载、不切分支')
    args = parser.parse_args(argv)
    if args.branch in ('main', 'master') or not args.branch.startswith('feat/'):
        raise SetupError('只允许feat/功能分支，不能在main/master实现。')
    if not shutil.which('git'):
        raise SetupError('缺少git，请先安装并配置GitHub仓库访问。')
    if run(['git', 'check-ref-format', '--branch', args.branch], capture=True, check=False).returncode:
        raise SetupError('分支名非法。')
    root = args.root.expanduser().resolve()
    # Inspect all existing repositories before cloning/switching any repository.
    for name in REPOSITORIES:
        repo = root / name
        if repo.exists():
            validate_repository(repo, name)
    if args.check_only:
        print(json.dumps({'root': str(root), 'git_available': True,
                          'claude_available': bool(shutil.which('claude')),
                          'repositories': {n: (root/n).is_dir() for n in REPOSITORIES}}, ensure_ascii=False, indent=2))
        return 0
    root.mkdir(parents=True, exist_ok=True)
    gh = shutil.which('gh')
    use_gh = bool(gh and run([gh, 'auth', 'status'], capture=True, check=False).returncode == 0)
    for name in REPOSITORIES:
        repo = root / name
        if not repo.exists():
            print(f'下载 maibanku/{name} → {repo}', flush=True)
            if use_gh:
                run([gh, 'repo', 'clone', f'maibanku/{name}', repo])
            else:
                run(['git', 'clone', f'https://github.com/maibanku/{name}.git', repo])
        validate_repository(repo, name)
    prompt = root / 'ppb-docs/iam/implementation/CLAUDE_CODE_PROMPT.md'
    # Check prompt before branch mutation; existing docs may need a user-controlled update.
    if not prompt.is_file():
        raise SetupError('本地ppb-docs缺少实施提示词，请先以正常Git流程更新该仓库后重试。')
    states = {}
    for name in REPOSITORIES:
        states[name] = prepare_branch(root / name, args.branch)
    if not prompt.is_file():
        raise SetupError('目标文档分支没有实施提示词，请合入最新文档提交后重试；未自动覆盖分支。')
    print(json.dumps({'workspace': str(root), 'repositories': states}, ensure_ascii=False, indent=2), flush=True)
    if args.prepare_only:
        print('下载与分支准备完成；未启动Claude Code、未调用模型、未修改供应商配置。')
        return 0
    return launch(root, prompt, args.branch)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except SetupError as exc:
        print(f'准备/启动未完成：{exc}', file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print('已中断；保留现有下载与分支，不删除工作目录。', file=sys.stderr)
        sys.exit(130)
