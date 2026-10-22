#!/bin/bash
# 外部への書き込み（Google ドキュメント更新、git push）を、オーナーの指示があった時だけ通す。
# 指示があったら .claude/write-approved に、指示の文言を書いてから実行する。10分で失効。
# 通らなかった試みは .claude/hook.log に残す（失敗の記録は消さない）。通った記録は追跡外の .claude/hook-allowed.log に書く。
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name')
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
root="$(git rev-parse --show-toplevel 2>/dev/null)"
log="$root/.claude/hook.log"
need=0
case "$tool" in
  mcp__MCP__google-workspace___batch_update_doc|mcp__MCP__google-workspace___find_and_replace_doc|mcp__MCP__google-workspace___create_doc|mcp__MCP__google-workspace___modify_doc_text|mcp__MCP__google-workspace___insert_doc_elements|mcp__MCP__google-workspace___update_paragraph_style) need=1 ;;
  Bash) echo "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push' && need=1 ;;
esac
[ "$need" = 1 ] || exit 0
ok="$root/.claude/write-approved"
if [ -f "$ok" ] && [ $(( $(date +%s) - $(stat -c %Y "$ok") )) -lt 600 ]; then
  echo "$(date -Is) allowed $tool :: $(head -c 120 "$ok" | tr '\n' ' ')" >> "$root/.claude/hook-allowed.log"
  exit 0
fi
echo "$(date -Is) BLOCKED $tool :: ${cmd:0:120}" >> "$log"
echo "書き込みはオーナーの指示があった項目だけ。指示の文言を .claude/write-approved に書いてから実行する（10分で失効）。この試みは .claude/hook.log に記録した。" >&2
exit 2
