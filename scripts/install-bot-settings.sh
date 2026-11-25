#!/usr/bin/env bash
# bots/_settings.json.tmpl（読み取りと Run の中の軽い操作の事前許可）を、このチームの bot の .claude/settings.json に配る。
#   使い方: install-bot-settings.sh <team.config> [役割のスラッグ…]
#   役割を省くと PMO 以外の 10 体。PMO は render-pmo.sh --install が配る。
# 既存の .claude/settings.json は .bak を残して置き換える。
set -euo pipefail
cfg=${1:?使い方: install-bot-settings.sh <team.config> [役割…]}; shift
# shellcheck disable=SC1090
. "$cfg"
here=$(cd "$(dirname "$0")/.." && pwd)
TEAM_CODE=${TEAM_CODE-}
P=${TEAM_CODE:+${TEAM_CODE}-}
. "$here/scripts/names.sh"
roles=${*:-reviewer ci-guardian intake fixer doc-keeper conductor sentinel release-captain ops-scribe planner}

bot_dir() { # bot 名 → ~/.orca/bots/<フォルダ>（フォルダ名は信用せず bot.json の name で引く）
  python3 - "$1" <<'PY'
import json,glob,os,sys
hits=[os.path.dirname(p) for p in glob.glob(os.path.expanduser('~/.orca/bots/*/bot.json'))
      if json.load(open(p)).get('name')==sys.argv[1]]
if len(hits)!=1: sys.exit(f'bot が {len(hits)} 件見つかった: {sys.argv[1]}')
print(hits[0])
PY
}

for r in $roles; do
  name=$(bot_name "$r")
  d=$(bot_dir "$name")
  mkdir -p "$d/.claude"
  [ -f "$d/.claude/settings.json" ] && cp "$d/.claude/settings.json" "$d/.claude/settings.json.bak"
  render_settings "$REPO_PATH" "${DEFAULT_BRANCH:-main}" "$(workspaces_dir)" "$(sweep_script)" "$d" "$(guard_script)" > "$d/.claude/settings.json"
  echo "配布: ${name} → ${d}/.claude/settings.json"
done
