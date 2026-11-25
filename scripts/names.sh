# 命名規則（render.sh / setup-automations.sh / render-pmo.sh が source する）。
# 前提: TEAM_CODE（空でよい）と P（"" か "<code>-"）が決まっていること。

# 役割のスラッグ → このチームでの bot 名
bot_name() {
  if [ -n "${TEAM_CODE-}" ]; then
    printf '%s%s\n' "$P" "$1"
    return
  fi
  case "$1" in
    reviewer) echo 'Reviewer' ;;
    ci-guardian) echo 'CI Guardian' ;;
    intake) echo 'Intake' ;;
    fixer) echo 'Fixer' ;;
    doc-keeper) echo 'Doc Keeper' ;;
    conductor) echo 'Conductor' ;;
    sentinel) echo 'Sentinel' ;;
    release-captain) echo 'Release Captain' ;;
    ops-scribe) echo 'Ops Scribe' ;;
    planner) echo 'Planner' ;;
    pmo) echo 'PMO' ;;
    *) echo "未知の役割: $1" >&2; return 1 ;;
  esac
}

# Orca がワーカーの作業場所を作るフォルダ（既定は ~/orca/workspaces/<リポジトリのフォルダ名>）
workspaces_dir() {
  if [ -n "${WORKSPACES_DIR:-}" ]; then echo "$WORKSPACES_DIR"
  elif [ -n "${REPO_PATH:-}" ]; then echo "$HOME/orca/workspaces/$(basename "$REPO_PATH")"
  fi
}

# bots/_settings.json.tmpl → 標準出力
# $1=リポジトリのパス（空なら {{REPO_PATH}} を含む規則を落とす）。$2=既定ブランチ。
# $3=作業場所のフォルダ（空なら {{WORKSPACES_DIR}} を含む規則を落とす）
# $4=見回りのスクリプト（空なら {{SWEEP}} を含む規則を落とす）
# $5=bot のフォルダの絶対パス（空なら {{BOT_DIR}} を含む規則を落とす）。Claude Code の Edit/Write の規則では
#    絶対パスを // で書くので、{{BOT_DIR}} には先頭に / を 1 つ足して入れる（{{BOT_HOME}} はそのまま）
# $6=判定フック（bot-guard.py。空ならフックを入れない。PMO など）
render_settings() {
  RP="$1" DB="${2:-main}" WS="${3:-}" SW="${4:-}" BH="${5:-}" GD="${6:-}" python3 - "$here/bots/_settings.json.tmpl" <<'PY'
import json,os,sys
e=os.environ
v={'{{REPO_PATH}}':e['RP'],'{{DEFAULT_BRANCH}}':e['DB'],'{{WORKSPACES_DIR}}':e['WS'],'{{SWEEP}}':e['SW'],
   '{{BOT_DIR}}':('/'+e['BH']) if e['BH'] else '','{{BOT_HOME}}':e['BH'],'{{GUARD}}':e['GD']}
def r(x):
    for k,val in v.items(): x=x.replace(k,val)
    return x
def keep(x): return all(val or k not in x for k,val in v.items())
d=json.load(open(sys.argv[1]))
for k in ('allow','deny'):
    d['permissions'][k]=[r(x) for x in d['permissions'][k] if keep(x)]
hooks=d.pop('hooks',None)
if hooks and all(v[k] for k in ('{{GUARD}}','{{REPO_PATH}}','{{WORKSPACES_DIR}}','{{BOT_HOME}}')):
    d['hooks']=json.loads(r(json.dumps(hooks,ensure_ascii=False)))
d['$comment']=r(d['$comment'])
print(json.dumps(d,ensure_ascii=False,indent=2))
PY
}

# 見回りのスクリプト（テンプレートの置き場所にあるものを直接使う。bot を動かすホストにこのテンプレートがあること）
sweep_script() { echo "$here/scripts/sweep.sh"; }
# 判定フック（bot の .claude/settings.json の PreToolUse から呼ぶ）
guard_script() { echo "$here/scripts/bot-guard.py"; }

# dev | ship → このチームでのルーム名
room_name() {
  local base
  case "$1" in dev) base='開発' ;; ship) base='出荷' ;; *) return 1 ;; esac
  if [ -n "${TEAM_CODE-}" ]; then
    printf '%s %s\n' "$TEAM_CODE" "$base"
  else
    printf '%sルーム\n' "$base"
  fi
}
