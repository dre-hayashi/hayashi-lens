#!/usr/bin/env python3
"""スキルの文が、記録にある本人の言葉の書き写しになっていないかを機械で照合する。
使い方:
  transcribe_check.py scan          スキル全体を照合し、重なりの大きい文を一覧にする
  transcribe_check.py diff          HEAD からの追加行だけを照合し、重なりがあれば 1 で終わる
照合の元: docs/casestudies.md の「」の中（本人の言葉）と、10/20 の対話の記録。スキルやファイルを引いた行は除く。
重なり: 本人の言葉の 3 文字の並びのうち、スキルの一文に含まれる割合。
読み解き（5Why と本人の確認）が docs/skill_provenance.md に記録されている言葉は通す。"""
import re, subprocess, sys, pathlib

root = pathlib.Path(subprocess.run(['git','rev-parse','--show-toplevel'],capture_output=True,text=True).stdout.strip())
SKILL = root/'.claude/skills/hayashi-lens'
REC = root/'docs/casestudies.md'
PROV = root/'docs/skill_provenance.md'
TH = 0.6      # 重なりの割合
MINQ = 15     # 照合する言葉の最短の長さ
SKIP_LINE = re.compile(r'core\.md|core |辿り方|scenes/|style\.md|feedback\.md|checks\.md|SKILL|persona|audit\.md|スキルの読み|スキルの返事|返事：|Claude の')

def norm(t):
    return re.sub(r'[\s　、。・「」『』（）()…\-—？?！!：:，,．.／/]', '', t)

def grams(t, n=3):
    t = norm(t)
    return {t[i:i+n] for i in range(len(t)-n+1)}

def quotes():
    out = []
    for line in REC.read_text().splitlines():
        if SKIP_LINE.search(line):
            continue
        for q in re.findall(r'「([^「」]{%d,})」' % MINQ, line):
            for part in re.split(r'[。？?]', q):
                if len(norm(part)) >= MINQ:
                    out.append(part.strip())
    # 10/20 の対話は、本人の判断を原文に近く書いた記録。「」が付いていないので、文ごとに足す
    lines = REC.read_text().splitlines()
    try:
        a = next(i for i, l in enumerate(lines) if l.startswith('## 2026-10-20 対話'))
        b = next(i for i, l in enumerate(lines) if l.startswith('## 議事録由来'))
        for l in lines[a:b]:
            if l.startswith('#'):
                continue
            l = re.sub(r'→.*$', '', l)
            for part in re.split(r'[。]', l):
                if len(norm(part)) >= MINQ:
                    out.append(part.strip())
    except StopIteration:
        pass
    return list(dict.fromkeys(out))

def cleared():
    if not PROV.exists():
        return set()
    t = PROV.read_text()
    m = re.search(r'^## 通してよい言葉.*?(?=^## |\Z)', t, re.S | re.M)
    return {norm(q) for q in re.findall(r'「([^「」]+)」', m.group(0))} if m else set()

def sentences(text):
    for s in re.split(r'[。\n]', text):
        s = s.strip()
        if len(norm(s)) >= 10:
            yield s

def check(sents, qs, ok):
    hits = []
    qg = [(q, grams(q)) for q in qs if norm(q) not in ok]
    for where, s in sents:
        sg = grams(s)
        best = None
        for q, g in qg:
            if len(g) < 10: continue
            r = len(g & sg) / len(g)
            if r >= TH and (best is None or r > best[0]):
                best = (r, q)
        if best:
            hits.append((where, s, best[0], best[1]))
    return hits

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'scan'
    qs, ok = quotes(), cleared()
    if mode == 'scan':
        sents = []
        for f in sorted(SKILL.rglob('*.md')):
            for s in sentences(f.read_text()):
                sents.append((str(f.relative_to(SKILL)), s))
    else:
        # 新しく足した文だけを照合する。HEAD に既にあった文は、行が書き換わっても対象にしない
        # （既にある重なりは docs/skill_provenance.md の未処理の列で追う）
        d = subprocess.run(['git','diff','HEAD','--unified=0','--','.claude/skills/hayashi-lens'],capture_output=True,text=True,cwd=root).stdout
        sents, had, cur = [], set(), None
        for line in d.splitlines():
            if line.startswith('+++ b/'):
                cur = line[6:]
                old = subprocess.run(['git','show','HEAD:'+cur],capture_output=True,text=True,cwd=root).stdout
                had = {norm(x) for x in sentences(old)}
            elif line.startswith('+') and not line.startswith('+++'):
                for s in sentences(line[1:]):
                    if norm(s) not in had:
                        sents.append((cur or '追加行', s))
    hits = check(sents, qs, ok)
    for where, s, r, q in hits:
        print(f'[{where}] 重なり {r:.0%}\n  スキル: {s[:110]}\n  本人の言葉: {q[:110]}')
    print(f'照合した言葉 {len(qs)} 件、照合した文 {len(sents)} 件、重なり {len(hits)} 件', file=sys.stderr)
    sys.exit(1 if (mode == 'diff' and hits) else 0)

main()
