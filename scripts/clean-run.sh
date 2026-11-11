#!/bin/bash
# まっさらな環境でスキルを実行する。スキルの実行は、必ずこれを使う。
# 使い方: scripts/clean-run.sh <実行用の親フォルダ（リポジトリの外）> <ケースのフォルダ名> <往復の番号> <new|resume> <入力文のファイル名>
#   例: scripts/clean-run.sh /tmp/hl-clean c7 1 new p1.txt
# 先に用意するもの：<親フォルダ>/<ケース>/ に、入力文のファイルと、持ち込みの資料（あれば）。スキルの写しはこのスクリプトが置く。
# 渡らないもの：リポジトリの CLAUDE.md とフック（フォルダがリポジトリの外）、外部の接続先（--strict-mcp-config）、
#   ほかのスキル（呼べるのは hayashi-lens だけ）、本人の判断の記録。
# 実行の後に、読んだ先・使った道具・CLAUDE.md の文が入っていないかを表示する。フォルダの外を読んでいたら、その実行は使わない。
# 2026-11-10：この作業場の中に別の作業者を立てて実行したところ、CLAUDE.md が全部の実行に渡っていた（本人「まっさらな環境でテストできないのでは意味がない」）。
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
ok="$root/.claude/design-approved"
if [ ! -f "$ok" ] || [ $(( $(date +%s) - $(stat -c %Y "$ok") )) -ge 21600 ]; then
  echo "ケースの設定に本人の確認が無い（.claude/design-approved が無いか、6時間を過ぎている）。実行しない。" >&2; exit 2
fi
P=$1; c=$2; t=$3; mode=$4; pf=$5
case "$P" in "$root"*) echo "実行用のフォルダはリポジトリの外に置く。" >&2; exit 2;; esac
D="$P/$c"
[ -d "$D" ] || { echo "$D が無い。" >&2; exit 2; }
if [ "$mode" = new ]; then
  mkdir -p "$D/.claude/skills" "$P/home"
  cp -r "$root/.claude/skills/hayashi-lens" "$D/.claude/skills/"
  git -C "$root" rev-parse --short HEAD > "$D/skill_commit"
fi
cd "$D" || exit 1
if [ "$mode" = new ]; then sid=$(cat /proc/sys/kernel/random/uuid); echo "$sid" > sid; sess="--session-id $sid"; else sess="--resume $(cat sid)"; fi
HOME="$P/home" claude -p --model opus $sess --strict-mcp-config --permission-mode acceptEdits \
  --allowedTools "Skill(hayashi-lens)" Read Write Edit Glob Grep Agent Task \
  --output-format stream-json --verbose < "$pf" > "out_t$t.jsonl" 2> "err_t$t.log"
python3 "$root/scripts/clean-run-parse.py" "$D" "$t"
