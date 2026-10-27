#!/bin/bash
# Stop フック：このターンの Claude の最終返答に、逃げ道の言い回しがあれば差し戻す。
# 逃げ道＝失敗を先に言い訳しておく言い方、判断をオーナーに預ける言い方、条件や推量で判断をぼかす言い方。
# 本人の指示（2026-10-27）「おまえ自身が逃げ道を常に用意しておくって動き方してるじゃないか。やめろよ。仕組みとしてそれをふさげ」。
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
pat='保証はできません|保証できません|保証しかねます|想定です|想定になります|かもしれません|可能性があります|違っていれば|間違っていれば|判断に従います|指示をいただければ|一言いただければ|よろしければ|と思います|でしょう|はずです|場合によっては|次第です|確かめるところで|測るところで確かめ|動くかは'
hits=$(echo "$last" | grep -oE "$pat" | sort -u | tr '\n' ' ')
[ -n "$hits" ] || exit 0
echo "$(date -Is) ESCAPE :: $hits" >> "$root/.claude/hook.log"
echo "逃げ道の言い回しがある：$hits。判断は言い切る。決められないなら、何の事実があれば決められるかを一つ書く。失敗の言い訳を先に置かない。判断をオーナーに預けない。この言い回しを消して出し直す。" >&2
exit 2
