#!/usr/bin/env python3
"""ppb-docs/mail 的静态一致性检查。

用法（在 ppb-docs/mail 目录下）：
    python3 -I tools/check_docs.py .

检查四类问题：
  1. 相对链接指向的文件不存在
  2. 引用了没有定义的编号：规则（如 A09-3）、功能点（FP-xx）、验收条目（MAC-nn、AC-nn）、
     非功能需求（NFR-Mxx、NFR-Nxx）、需求组（MAIL-nn）、通知邮件修复项（F1 到 F13）
  3. 形如"见 [某文档](路径) 第 N 节"的章节号在目标文档里不存在
  4. 表格各行的列数与表头不一致
  5. 目录里混进了不属于文档集的文件（ac/evidence 之外的非 md、sql、sh、py、pen 文件）

通过时输出 NO PROBLEMS 且退出码为 0。只做静态检查，不能代替评审。
"""
import os, re, sys, glob

ROOT = os.path.abspath(sys.argv[1])
files = sorted(glob.glob(os.path.join(ROOT, '**', '*.md'), recursive=True))
texts = {f: open(f, encoding='utf-8').read() for f in files}
rel = lambda f: os.path.relpath(f, ROOT)
problems = []

def defined_ids(path_prefix, pattern):
    ids = set()
    for f, t in texts.items():
        if rel(f).startswith(path_prefix):
            for line in t.splitlines():
                m = re.match(r'^\|\s*(' + pattern + r')\s*\|', line)
                if m:
                    ids.add(m.group(1))
                m2 = re.match(r'^### (' + pattern + r')\b', line)
                if m2:
                    ids.add(m2.group(1))
    return ids

def heading_ids(path_prefix, pattern):
    ids = set()
    for f, t in texts.items():
        if rel(f).startswith(path_prefix):
            for line in t.splitlines():
                m = re.match(r'^#{2,4} (' + pattern + r')\b', line)
                if m:
                    ids.add(m.group(1))
    return ids

# ---------- 1. links ----------
link_re = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
nlinks = 0
for f, t in texts.items():
    # strip code fences
    body = re.sub(r'```.*?```', '', t, flags=re.S)
    for m in link_re.finditer(body):
        tgt = m.group(1)
        if tgt.startswith(('http://', 'https://', 'mailto:')):
            continue
        nlinks += 1
        path = tgt.split('#')[0]
        if not path:
            continue
        full = os.path.normpath(os.path.join(os.path.dirname(f), path))
        if not os.path.exists(full):
            problems.append(f'BROKEN LINK {rel(f)} -> {tgt}')

# anchors to headings inside same repo docs (## N. 标题)
def headings(f):
    out = {}
    for line in texts[f].splitlines():
        m = re.match(r'^#{2,4} (\d+(?:\.\d+)*)[\. ]', line)
        if m:
            out[m.group(1)] = line
    return out

# ---------- 2. rule ids ----------
pr_rule = r'[A-Z]\d{2}-\d{1,2}[a-z]?'
defined_rules = defined_ids('pr/', pr_rule)
cited_missing = {}
for f, t in texts.items():
    body = re.sub(r'```.*?```', '', t, flags=re.S)
    for m in re.finditer(r'(?<![A-Za-z0-9-])(' + pr_rule + r')(?![0-9A-Za-z])', body):
        rid = m.group(1)
        # T 开头的是 ppb-mail/docs/verification/M1-技术核对.md 里核对条目的编号，
        # 不是本目录的规则；派工的任务书会引用它们。
        if rid[0] == 'T':
            continue
        if rid not in defined_rules:
            cited_missing.setdefault(rid, set()).add(rel(f))
for rid in sorted(cited_missing):
    problems.append(f'UNDEFINED RULE {rid} cited in {sorted(cited_missing[rid])}')

fp_defined = set(re.findall(r'\| (FP-[A-Z]\d{2}) \|', texts[os.path.join(ROOT, 'PRD.md')]))
fp_cited = {}
for f, t in texts.items():
    for m in re.finditer(r'FP-([A-Z])(\d{2})', t):
        fp_cited.setdefault(f'FP-{m.group(1)}{m.group(2)}', set()).add(rel(f))
for fp in sorted(fp_cited):
    if fp not in fp_defined:
        problems.append(f'UNDEFINED FP {fp} cited in {sorted(fp_cited[fp])}')

ac02 = os.path.join(ROOT, 'ac', '02-邮箱系统验收标准.md')
mac_defined = set(re.findall(r'^\| (MAC-\d+) \|', texts[ac02], flags=re.M))
mac_cited = {}
for f, t in texts.items():
    for m in re.finditer(r'MAC-(\d+)', t):
        mac_cited.setdefault('MAC-' + m.group(1), set()).add(rel(f))
for k in sorted(mac_cited):
    if k not in mac_defined:
        problems.append(f'UNDEFINED {k} cited in {sorted(mac_cited[k])}')

ac01 = os.path.join(ROOT, 'ac', '01-验收标准.md')
ac_defined = set(re.findall(r'^\| (AC-\d+) \|', texts[ac01], flags=re.M))
ac_cited = {}
for f, t in texts.items():
    for m in re.finditer(r'(?<![A-Z])AC-(\d+)', t):
        ac_cited.setdefault('AC-' + m.group(1), set()).add(rel(f))
for k in sorted(ac_cited):
    if k not in ac_defined:
        problems.append(f'UNDEFINED {k} cited in {sorted(ac_cited[k])}')

prd = texts[os.path.join(ROOT, 'PRD.md')]
nfr_defined = set(re.findall(r'\| (NFR-[MN]\d{2}) \|', prd))
nfr_cited = {}
for f, t in texts.items():
    for m in re.finditer(r'NFR-[MN](\d{2})', t):
        nfr_cited.setdefault(m.group(0), set()).add(rel(f))
for k in sorted(nfr_cited):
    if k not in nfr_defined:
        problems.append(f'UNDEFINED {k} cited in {sorted(nfr_cited[k])}')

mail_defined = heading_ids('pr/', r'MAIL-\d{2}')
for f, t in texts.items():
    for m in re.finditer(r'MAIL-(\d{2})(?!\d)', t):
        if 'MAIL-' + m.group(1) not in mail_defined:
            problems.append(f'UNDEFINED MAIL-{m.group(1)} cited in {rel(f)}')

# fix ids used in tech/11 (F1..F13) and Q/J ids in PROGRESS
fix_defined = set(re.findall(r'^\| (F\d+) \|', texts[os.path.join(ROOT, 'tech', '11-通知邮件缺口修复设计.md')], flags=re.M))
for f, t in texts.items():
    for m in re.finditer(r'(?<![A-Za-z])(F\d{1,2})(?![0-9A-Za-z])', t):
        if rel(f).startswith('tech/11') or 'ac/' in rel(f):
            if m.group(1) not in fix_defined:
                problems.append(f'UNDEFINED fix {m.group(1)} cited in {rel(f)}')

# ---------- 3. section references of the form [text](path) ... 第 N 节 ----------
sec_re = re.compile(r'\[([^\]]+)\]\(([^)]+)\)[^\n]{0,16}?第 (\d+(?:\.\d+)?) 节')
cache = {}
nsec = 0
for f, t in texts.items():
    body = re.sub(r'```.*?```', '', t, flags=re.S)
    for m in sec_re.finditer(body):
        path, num = m.group(2).split('#')[0], m.group(3)
        if path.startswith('http'):
            continue
        full = os.path.normpath(os.path.join(os.path.dirname(f), path))
        if not os.path.exists(full):
            continue
        if full not in cache:
            cache[full] = headings(full)
        nsec += 1
        if num not in cache[full]:
            problems.append(f'BAD SECTION REF {rel(f)} -> {rel(full)} 第 {num} 节')
print(f'files={len(files)} links={nlinks} section_refs={nsec}')

# ---------- 4. table shape ----------
for f, t in texts.items():
    lines = t.splitlines()
    in_code = False
    i = 0
    while i < len(lines):
        if lines[i].startswith('```'):
            in_code = not in_code
        if not in_code and lines[i].lstrip().startswith('|') and i + 1 < len(lines) and re.match(r'^\s*\|[\s:|-]+\|\s*$', lines[i + 1]):
            ncol = lines[i].count('|') - 1
            j = i + 2
            while j < len(lines) and lines[j].lstrip().startswith('|'):
                c = lines[j].count('|') - 1
                if c != ncol:
                    problems.append(f'TABLE SHAPE {rel(f)}:{j + 1} has {c} cols, header {ncol}')
                j += 1
            i = j
            continue
        i += 1

# ---------- 5. stray texts ----------
for f, t in texts.items():
    for pat in ['Postfox', 'ppb_base', 'TODO', 'TBD', '待补充内容']:
        if pat in t:
            problems.append(f'STRAY {pat!r} in {rel(f)}')

# ---------- 5b. files that do not belong to the doc set ----------
for p in sorted(glob.glob(os.path.join(ROOT, '**', '*'), recursive=True)):
    r = os.path.relpath(p, ROOT)
    if not os.path.isfile(p) or r.startswith('ac/evidence/'):
        continue
    if not p.endswith(('.md', '.sql', '.sh', '.py', '.pen')):
        problems.append(f'UNEXPECTED FILE {r}（不属于文档集，提交前移走）')

# ---------- report ----------
if problems:
    print(f'PROBLEMS: {len(problems)}')
    for p in problems:
        print(' -', p)
else:
    print('NO PROBLEMS')
print('rules defined:', len(defined_rules), '| FP defined:', len(fp_defined), '| MAC defined:', len(mac_defined), '| AC defined:', len(ac_defined), '| NFR defined:', sorted(nfr_defined))
sys.exit(1 if problems else 0)
