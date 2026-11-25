#!/usr/bin/env bash
# 全チーム共通の PMO の指示文を、チームの設定ファイル（team.*.config）の一覧から作る。
#   使い方: render-pmo.sh <team.config>…            … 指示文（SOUL.md 本文）を標準出力へ
#           render-pmo.sh --install <team.config>…  … PMO の SOUL.md を書き換え、.claude/settings.json と自動化 3 本を入れる
#   例: render-pmo.sh --install ~/orca-teams/team.*.config（PMO が見るすべてのチームの設定を渡す）
# PMO の bot は画面で 1 体だけ作っておく（名前は PMO）。チームを足したら --install を流し直す。
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
mode=''
if [ "${1-}" = "--install" ]; then mode=--install; shift; fi
[ $# -gt 0 ] || { echo "使い方: render-pmo.sh [--install] <team.config>…" >&2; exit 1; }

table='| チーム | リポジトリ | Project | ホスト上のパス | 規約 |
| --- | --- | --- | --- | --- |'
tz=''
n=0
for cfg in "$@"; do
  [ "$(basename "$cfg")" = "team.config.example" ] && continue
  # 各設定は別のサブシェルで読み、値が混ざらないようにする
  row=$( . "$cfg"; printf '| %s | `%s` | %s | `%s` | `%s` |' "$TEAM_NAME" "$REPO" "${PROJECT_URL:-（未作成）}" "$REPO_PATH" "${RULES_DOC:-CLAUDE.md}" )
  [ -n "$tz" ] || tz=$( . "$cfg"; printf '%s' "${TZ_LABEL:-日本時間}" )
  table="$table
$row"
  n=$((n+1))
done
[ "$n" -gt 0 ] || { echo "チームの設定ファイルが無い（team.config.example は数えない）" >&2; exit 1; }

doc=$(cat "$here/shared/pmo.md.tmpl")
doc=${doc//\{\{TEAMS_TABLE\}\}/$table}
doc=${doc//\{\{TZ_LABEL\}\}/$tz}
soul=$(printf '%s\n' "$doc" | python3 -c '
import re,sys
m=re.search(r"## SOUL\.md 本文\s*\n\s*```markdown\n(.*?)\n```\s*\n(?=## )", sys.stdin.read(), re.S)
print(m.group(1))')

if [ "$mode" != "--install" ]; then
  printf '%s\n' "$soul"
  exit 0
fi

d=$(python3 - <<'PY'
import json,glob,os,sys
hits=[os.path.dirname(p) for p in glob.glob(os.path.expanduser('~/.orca/bots/*/bot.json'))
      if json.load(open(p)).get('name')=='PMO']
if len(hits)!=1: sys.exit(f'PMO が {len(hits)} 体見つかった。画面で 1 体だけ作る')
print(hits[0])
PY
)
SOUL="$soul" P="$d/SOUL.md" python3 - <<'PY'
import os,re,io
p=os.environ['P']; body=os.environ['SOUL'].rstrip('\n')
cur=io.open(p,encoding='utf-8').read() if os.path.exists(p) else ''
m=re.search(r'\n## Never\n.*', cur, re.S)
out=body+('\n\n'+m.group(0).strip('\n') if m else '')+'\n'
io.open(p,'w',encoding='utf-8').write(out)
print('SOUL.md を書き換えた:', p)
PY
mkdir -p "$d/.claude"
[ -f "$d/.claude/settings.json" ] && cp "$d/.claude/settings.json" "$d/.claude/settings.json.bak"
. "$here/scripts/names.sh"
render_settings "" main > "$d/.claude/settings.json"
echo "settings.json を配った: $d/.claude/settings.json"

existing=$(orca automations list --json | python3 -c 'import json,sys; print("\n".join(a["name"] for a in json.load(sys.stdin).get("result",{}).get("automations",[])))')
TIMEZONE=${TIMEZONE:-Asia/Tokyo}
mk() { # <name> <rrule> <prompt>
  if printf '%s\n' "$existing" | grep -qxF "$1"; then echo "既存: $1"; return 0; fi
  orca automations create --bot PMO --name "$1" --trigger "$2" --timezone "$TIMEZONE" --prompt "$3" --enabled --json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(("作成: " if d.get("ok") else "NG:   ")+sys.argv[1])' "$1"
}
mk "PMO: スタンドアップ" "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0" \
  "SOUL.md の「スタンドアップ」を、見るチームの表のチームごとに実行してください。未レビューのエージェント作業も一緒に出してください。"
mk "PMO: 週次ブリーフィング" "FREQ=WEEKLY;BYDAY=FR;BYHOUR=15;BYMINUTE=0" \
  "SOUL.md の「週次ブリーフィング」を、チームごとに実行してください。"
mk "PMO: worktree の整理" "FREQ=WEEKLY;BYDAY=FR;BYHOUR=16;BYMINUTE=0" \
  "SOUL.md の「worktree の整理」を実行してください。worktree は自分で消さず、一覧を出すだけにしてください。"
