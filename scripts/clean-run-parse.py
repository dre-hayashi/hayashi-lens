import json, sys, os
# 使い方: parse.py <ケースのフォルダ> <往復の番号>
d0, t = sys.argv[1], sys.argv[2]
os.chdir(d0)
res = ''
skills = []
tools = {}
paths = set()
denied = 0
raw = open(f'out_t{t}.jsonl', encoding='utf-8').read()
for line in raw.splitlines():
    try:
        d = json.loads(line)
    except Exception:
        continue
    if not isinstance(d, dict):
        continue
    if d.get('type') == 'result':
        res = d.get('result') or ''
    m = d.get('message')
    c = m.get('content') if isinstance(m, dict) else None
    if d.get('type') == 'assistant' and isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get('type') == 'tool_use':
                n = b.get('name')
                tools[n] = tools.get(n, 0) + 1
                i = b.get('input') or {}
                if n == 'Skill':
                    skills.append(i.get('skill'))
                for k in ('file_path', 'path'):
                    if i.get(k):
                        paths.add(i[k])
    if d.get('type') == 'user' and isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get('type') == 'tool_result':
                s = json.dumps(b, ensure_ascii=False)[:500].lower()
                if 'denied' in s or 'permission' in s:
                    denied += 1
open(f'reply_t{t}.md', 'w').write(res.strip() + '\n')
here = os.getcwd()
outside = sorted(p for p in paths if not os.path.abspath(os.path.join(here, p)).startswith(here))
print(f'done t{t}: 返事 {len(res)} 字')
print(' 呼んだスキル:', skills)
print(' 使った道具:', tools)
print(' フォルダの外を読んだ先:', outside)
print(' 止められた呼び出し:', denied)
print(' CLAUDE.md の文:', raw.count('hayashi-lens を扱うときの約束'))
