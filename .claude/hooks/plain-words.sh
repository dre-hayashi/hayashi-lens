#!/bin/bash
# Stop フック：このターンの Claude の最終返答に、Claude が作った言い回しやスキルの内部の呼び名があれば差し戻す。
# 本人の指摘（2026-11-10）：「君独自の変な日本語で説明しないように。普通の言葉で説明しなさい。鎖だとか段だとか道だとか、そんな説明は日本人はしない」
# 注意書きを毎ターン出すだけでは直らなかったので、出す所で止める。
# 一ターンにつき一度だけ差し戻す（stop_hook_active なら通す）。差し戻しは .claude/hook.log に残す。
input=$(cat)
echo "$input" | jq -e '.stop_hook_active == true' >/dev/null 2>&1 && exit 0
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -f "$transcript" ] || exit 0
root="$(cd "$(dirname "$0")/../.." && pwd)"
last=$(python3 - "$transcript" <<'PY'
import json,sys
last=''
for line in open(sys.argv[1],encoding='utf-8'):
    try: d=json.loads(line)
    except: continue
    t=d.get('type'); c=(d.get('message') or {}).get('content')
    if t=='user':
        if isinstance(c,str) or (isinstance(c,list) and c and c[0].get('type')=='text'): last=''
    elif t=='assistant' and isinstance(c,list):
        for b in c:
            if b.get('type')=='text' and b.get('text','').strip(): last=b['text']
print(last)
PY
)
[ -n "$last" ] || exit 0
# 照合は python で行う（grep は環境の文字コード設定によって「段階」を「段＋数字」と取り違える）
hits=$(printf '%s' "$last" | python3 -c '
import re,sys
pat=r"鎖|道筋|見立て|物差し|土台|辿り方|段[0-9０-９]|段ごと|道を書く|道に数え|道の一"
print(" ".join(sorted(set(re.findall(pat,sys.stdin.read())))))
')
[ -n "$hits" ] || exit 0
echo "$(date -Is) PLAIN-WORDS :: $hits" >> "$root/.claude/hook.log"
echo "オーナーへの返答に、自分で作った言い回しやスキルの内部の呼び名がある：$hits。普通の日本語に書き直して出し直す。何を、どこで、どう変えるかを、内部の呼び名を使わずに書く。" >&2
exit 2
