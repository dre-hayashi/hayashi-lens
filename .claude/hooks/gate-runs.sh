#!/bin/bash
# PreToolUse フック（Bash）：スキルの実行（claude -p、runner.sh）を、ケースの設定にオーナーの確認があった時だけ通す。
# 2026-11-02、設計の確認を飛ばしてケース6〜9を走らせ、クレジットを無駄にした。同じ形を仕組みで塞ぐ。
# 確認を得たら .claude/design-approved に、確認の文言（どのケースの設定か）を書いてから実行する。6時間で失効。
# 止めた試みは .claude/hook.log に残す。
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name')
[ "$tool" = Bash ] || exit 0
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
echo "$cmd" | grep -Eq '(^|[;&|[:space:]/])(claude[[:space:]]+(-p|--print)|runner\.sh)' || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)"
ok="$root/.claude/design-approved"
if [ -f "$ok" ] && [ $(( $(date +%s) - $(stat -c %Y "$ok") )) -lt 21600 ]; then
  echo "$(date -Is) run-allowed :: $(head -c 160 "$ok" | tr '\n' ' ')" >> "$root/.claude/hook-allowed.log"
  exit 0
fi
echo "$(date -Is) BLOCKED-RUN Bash :: ${cmd:0:120}" >> "$root/.claude/hook.log"
echo "スキルの実行は、ケースの設定（事実・水準・設定・根拠）をオーナーに見せ、確認を得てから。確認の文言を .claude/design-approved に書いてから実行する（6時間で失効）。この試みは .claude/hook.log に記録した。" >&2
exit 2
