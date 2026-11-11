#!/bin/bash
# PreToolUse フック（Bash）：スキルを変えたコミットを、二つの照合に通ったときだけ通す。
# 1) 追加した文が、記録にある本人の言葉の書き写しになっていない（transcribe_check.py diff）。
# 2) その変更の元（どの判断から、5Why はどこか、本人の確認の言葉）が docs/skill_provenance.md に書かれている。
# 2026-11-10、10/22 の言葉が 5Why を経ずにスキルに入り、10/22・10/24・10/27・11/02 の検査を全部すり抜けていたと分かった。
# これまでの検査は、頼まれたときに別のエージェントの目で読むものだった。変更のたびに機械で必ず走る形にする。
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name')
[ "$tool" = Bash ] || exit 0
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
echo "$cmd" | grep -Eq 'git[[:space:]]+commit' || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$root" || exit 0
changed=$(git status --porcelain | awk '{print $NF}')
echo "$changed" | grep -q '^.claude/skills/hayashi-lens/' || exit 0
out=$(python3 "$root/.claude/hooks/transcribe_check.py" diff 2>&1)
if [ $? -ne 0 ]; then
  echo "$(date -Is) BLOCKED-TRANSCRIBE :: ${cmd:0:80}" >> "$root/.claude/hook.log"
  echo "スキルに足した文が、記録にある本人の言葉と重なっている。言葉をそのまま入れない。5Why にかけ、どの席で、何を見て、なぜそう判断するかの形に書き直す。" >&2
  echo "$out" >&2
  exit 2
fi
if ! echo "$changed" | grep -q '^docs/skill_provenance.md$'; then
  echo "$(date -Is) BLOCKED-PROVENANCE :: ${cmd:0:80}" >> "$root/.claude/hook.log"
  echo "スキルを変えたのに、docs/skill_provenance.md に元の記録が無い。どの判断から、5Why はどこか、本人の確認の言葉は何かを書いてからコミットする。" >&2
  exit 2
fi
exit 0
