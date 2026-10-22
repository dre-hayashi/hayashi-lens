#!/bin/bash
# Stop フック：このターンで hayashi-lens スキルを実行していれば、最終出力（FB）を監査役に照らす。
# 照らす先は references/audit.md に書いた通り、core.md の辿り方と feedback.md だけ。新しい規則は持たない。
# fail なら exit 2 で一度だけ差し戻し、本体に findings を返す。本体は一件ずつ入れる／入れないを答えて一度で出し直す。往復はしない。監査役が動かなければ記録して通す。
# 監査役はスキルを実行するモデルと同じ級（opus）。下のモデルでは読み落としと指摘の入れ替わりが出た（2026-10-22）。
# 再帰防止：環境変数 HAYASHI_LENS_AUDIT_NESTED を立てて /tmp から呼ぶ（この settings.json を読まない）。
[ -n "$HAYASHI_LENS_AUDIT_NESTED" ] && exit 0
input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -f "$transcript" ] || exit 0
echo "$input" | jq -e '.stop_hook_active == true' >/dev/null 2>&1 && STOP_ACTIVE=1 || STOP_ACTIVE=0

root="$(cd "$(dirname "$0")/../.." && pwd)"
ref="$root/.claude/skills/hayashi-lens/references"
work="$root/.claude/audit-work"
log="$root/.claude/audit.log"
mkdir -p "$work"
MAX=1

# このターン（最後のユーザー発話以降）の抽出：スキル実行の有無と最終出力
turn=$(python3 - "$transcript" <<'EOF'
import json,sys
p=sys.argv[1]; uid=None; skill=False; last=None
for line in open(p,encoding='utf-8'):
    try: d=json.loads(line)
    except: continue
    t=d.get('type'); m=d.get('message') or {}; c=m.get('content')
    if t=='user':
        is_prompt = isinstance(c,str) or (isinstance(c,list) and c and c[0].get('type')=='text')
        if is_prompt:
            uid=d.get('uuid'); skill=False; last=None
    elif t=='assistant' and isinstance(c,list):
        for b in c:
            if b.get('type')=='tool_use' and b.get('name')=='Skill' and (b.get('input') or {}).get('skill')=='hayashi-lens':
                skill=True
            if b.get('type')=='text' and b.get('text','').strip():
                last=b['text']
print(json.dumps({'uid':uid,'skill':skill,'last':last or ''}))
EOF
)
echo "$turn" | jq -e '.skill == true and (.last|length) > 0' >/dev/null 2>&1 || exit 0
uid=$(echo "$turn" | jq -r .uid)
echo "$turn" | jq -r .last > "$work/fb.md"

# 回数の管理（ターンごと）
state="$work/state"
if [ -f "$state" ] && [ "$(sed -n 1p "$state")" = "$uid" ]; then
  n=$(( $(sed -n 2p "$state") + 1 ))
else
  n=1
fi
printf '%s\n%s\n' "$uid" "$n" > "$state"
if [ "$n" -gt "$MAX" ]; then
  echo "$(date -Is) $uid 監査上限超過、通す（$n 回目）" >> "$log"
  exit 0
fi

# 監査役を呼ぶ
if ! command -v claude >/dev/null 2>&1; then
  echo "$(date -Is) $uid 監査不能（claude CLI なし）" >> "$log"
  exit 0
fi
memo="$work/memo.md"
{
  echo "# 監査役への指示"
  sed -n '/^## 監査役への指示/,/^## 出力/p' "$ref/audit.md" | sed '1d;$d'
  echo; echo "# 出力形式"
  sed -n '/^## 出力/,/^## やらないこと/p' "$ref/audit.md" | sed '1d;$d'
  echo; echo "# やらないこと"
  sed -n '/^## やらないこと/,/^## 本体の受け方/p' "$ref/audit.md" | sed '1d;$d'
  echo; echo "# 照らす先のファイル"
  for f in "$ref/core.md" "$ref/persona.md" "$ref/feedback.md" "$ref/style.md" "$ref/checks.md" "$ref"/scenes/*.md "$ref/knowledge/roles.md" "$ref"/modes/*.md; do
    echo; echo "## $(basename "$f")"; cat "$f"
  done
  echo; echo "# 持ち込まれた資料"
  if [ -f "$work/material.md" ]; then cat "$work/material.md"; else echo "（資料なし。資料に書かれていないことを前提にした指摘の照合は飛ばす）"; fi
  echo; echo "# 作業メモ"
  if [ -f "$memo" ]; then cat "$memo"; else echo "（メモなし）"; fi
  echo; echo "# 監査対象の FB"; cat "$work/fb.md"
  echo; echo "JSON だけを出力せよ。"
} > "$work/prompt.md"

schema='{"type":"object","properties":{"verdict":{"type":"string","enum":["pass","fail"]},"findings":{"type":"array","items":{"type":"object","properties":{"where":{"type":"string"},"what":{"type":"string"},"evidence":{"type":"string"}},"required":["where","what","evidence"]}},"memo":{"type":"string"}},"required":["verdict","findings","memo"]}'
result=$(cd /tmp && HAYASHI_LENS_AUDIT_NESTED=1 timeout 360 claude -p --model opus --output-format json --json-schema "$schema" --allowedTools StructuredOutput --disallowedTools Bash Read Write Edit Glob Grep WebSearch WebFetch Agent Skill < "$work/prompt.md" 2>"$work/err.txt")
verdictjson=$(echo "$result" | jq -c '.structured_output // empty' 2>/dev/null)
if [ -z "$verdictjson" ]; then
  verdictjson=$(echo "$result" | jq -r '.result // empty' 2>/dev/null | sed -n '/{/,$p' | jq -c . 2>/dev/null)
fi
if [ -z "$verdictjson" ]; then
  echo "$(date -Is) $uid 監査不能（応答が読めない）: $(head -c 200 "$work/err.txt" | tr '\n' ' ')" >> "$log"
  exit 0
fi
echo "$verdictjson" > "$work/result.json"
verdict=$(echo "$verdictjson" | jq -r .verdict)
count=$(echo "$verdictjson" | jq '.findings|length')
echo "$(date -Is) $uid 監査 $n 回目: $verdict findings=$count memo=$(echo "$verdictjson" | jq -r .memo)" >> "$log"
[ "$verdict" = "pass" ] && exit 0

findings=$(echo "$verdictjson" | jq -r '.findings[] | "- [\(.where)] \(.what)（根拠: \(.evidence)）"')
if [ "$n" -ge "$MAX" ]; then
  echo "監査（$n 回目、最終）が通らなかった。FB の末尾に「監査未通過」として以下を残し、ターンを終える。
$findings" >&2
  exit 2
fi
echo "監査（$n 回目／最大 $MAX 回）: fail。findings を一件ずつ取り、「入れる」か「入れない（feedback.md の上げないのどれに当たるか）」を答えてから、FB を出し直す。土台が崩れた後の継続と、役割の責任の問い残しは、理由を付けて入れないとは言えない。
$findings" >&2
exit 2
