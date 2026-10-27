#!/bin/bash
# PreToolUse フック（Write / Edit / Bash）：スキル本体・実験版・設計文書への書き込みに、逃げ道の言い回しがあれば止める。
# 逃げ道＝例外や「落ちない場合」、条件や推量で判断をぼかす言い方、断定を避ける言い方。言い訳理由になる（本人の指摘 2026-10-27）。
# 通すには、その言い回しが本人の判断の記録に根を持つことを .claude/escape-approved に書く（記録の場所を添える。10分で失効）。
# 止めた試みは .claude/hook.log に残す。
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name')
root="$(git rev-parse --show-toplevel 2>/dev/null)"
case "$tool" in
  Write) path=$(echo "$input" | jq -r '.tool_input.file_path // empty'); text=$(echo "$input" | jq -r '.tool_input.content // empty') ;;
  Edit)  path=$(echo "$input" | jq -r '.tool_input.file_path // empty'); text=$(echo "$input" | jq -r '.tool_input.new_string // empty') ;;
  Bash)  cmd=$(echo "$input" | jq -r '.tool_input.command // empty'); path=$(echo "$cmd" | grep -oE '(\.claude/skills/|experiments/|docs/design)[^ "'"'"']*' | head -1); text="$cmd" ;;
  *) exit 0 ;;
esac
echo "$path" | grep -qE '(\.claude/skills/|experiments/|docs/design)' || exit 0
pat='落ちない場合|無理に落とさない|場合による|場合もある|ことがある|ことはある|かもしれない|可能性がある|可能性はある|必須ではない|断定せず|保証|次第で|余地が|例外|原則として|概ね|なるべく|できれば|できるだけ|柔軟に|適宜|状況に応じて|ケースによる'
hits=$(printf '%s' "$text" | grep -oE "$pat" | sort -u | tr '\n' ' ')
[ -n "$hits" ] || exit 0
ok="$root/.claude/escape-approved"
if [ -f "$ok" ] && [ $(( $(date +%s) - $(stat -c %Y "$ok") )) -lt 600 ]; then
  echo "$(date -Is) escape-allowed $tool $path :: $hits :: $(head -c 160 "$ok" | tr '\n' ' ')" >> "$root/.claude/hook-allowed.log"
  exit 0
fi
echo "$(date -Is) ESCAPE-WRITE $tool $path :: $hits" >> "$root/.claude/hook.log"
echo "スキル・設計への書き込みに逃げ道の言い回しがある：$hits（$path）。例外や場合分けで判断を逃がさない。決める形（二択）に書き直す。本人の判断の記録に根があるなら、記録の場所を .claude/escape-approved に書いてから実行する（10分で失効）。この試みは .claude/hook.log に記録した。" >&2
exit 2
