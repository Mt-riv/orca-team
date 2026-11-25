#!/usr/bin/env bash
# orca-team のテンプレートを 1 つのリポジトリ向けに展開する。
# 使い方: scripts/render.sh <team.config>
set -euo pipefail

cfg=${1:?使い方: render.sh <team.config>}
here=$(cd "$(dirname "$0")/.." && pwd)

# shellcheck disable=SC1090
. "$cfg"

: "${REPO:?REPO が未設定}"
: "${REPO_PATH:?REPO_PATH が未設定}"
[ -d "$REPO_PATH" ] || { echo "REPO_PATH が見つからない: $REPO_PATH" >&2; exit 1; }

OWNER=${REPO%%/*}
CONFIG_FILE=$(basename "$cfg")
CONFIG_DIR=$(cd "$(dirname "$cfg")" && pwd)
CONFIG_PATH="$CONFIG_DIR/$CONFIG_FILE"
TEMPLATE_DIR=$here

# --- 命名規則（README「チームを増やすときの命名規則」）---
# TEAM_CODE が空 = 最初のチーム（bot 名は Reviewer のような表示名のまま）。
# TEAM_CODE がある = bot 名は <code>-<役割>（例 ml-reviewer）。名前とフォルダ名とメンション名が一致する。
TEAM_CODE=${TEAM_CODE-}
case "$TEAM_CODE" in
  '') P='' ;;
  *[!a-z0-9]*) echo "TEAM_CODE は英小文字と数字だけ: $TEAM_CODE" >&2; exit 1 ;;
  *) P="${TEAM_CODE}-" ;;
esac
. "$here/scripts/names.sh"
if [ -n "$TEAM_CODE" ]; then TEAM_CODE_LABEL="\`$TEAM_CODE\`"; else TEAM_CODE_LABEL="なし（最初のチーム）"; fi
WORKSPACES_DIR=$(workspaces_dir)
SWEEP_CMD="$(sweep_script) $REPO"
ADR_DIR=${ADR_DIR:-docs/adr}
REQ_DIR=${REQ_DIR:-docs/requirements}
PLAN_BRANCH_PREFIX=${PLAN_BRANCH_PREFIX:-plan/R-<issue>-<name>}
ROOM_DEV=${ROOM_DEV:-$(room_name dev)}
ROOM_SHIP=${ROOM_SHIP:-$(room_name ship)}
NAME_REVIEWER=$(bot_name reviewer);               NAME_CI_GUARDIAN=$(bot_name ci-guardian)
NAME_INTAKE=$(bot_name intake);                   NAME_FIXER=$(bot_name fixer)
NAME_DOC_KEEPER=$(bot_name doc-keeper);           NAME_CONDUCTOR=$(bot_name conductor)
NAME_SENTINEL=$(bot_name sentinel);               NAME_RELEASE_CAPTAIN=$(bot_name release-captain)
NAME_OPS_SCRIBE=$(bot_name ops-scribe);           NAME_PLANNER=$(bot_name planner)

KEYS="TEAM_NAME REPO REPO_PATH WORKSPACES_DIR ADR_DIR REQ_DIR PLAN_BRANCH_PREFIX OWNER DEFAULT_BRANCH PROJECT_TITLE PROJECT_NUMBER PROJECT_URL \
RULES_DOC SPEC_DOC PROCESS_DOC CHECK_CMD TEST_CMD BRANCH_PREFIX DEV_PROCESS DEPLOY_KIND \
TZ_LABEL ROOM_DEV ROOM_SHIP LABEL_CONDUCTOR LABEL_FIXER LABEL_INCIDENT BOT_HOST BOT_NAME CONFIG_FILE CONFIG_DIR CONFIG_PATH TEMPLATE_DIR TEAM_CODE P SWEEP_CMD \
NAME_REVIEWER NAME_CI_GUARDIAN NAME_INTAKE NAME_FIXER NAME_DOC_KEEPER NAME_CONDUCTOR \
NAME_SENTINEL NAME_RELEASE_CAPTAIN NAME_OPS_SCRIBE NAME_PLANNER BOT_SLUG TEAM_CODE_LABEL"

common=$(cat "$here/bots/_common.md")

# $1 = 本文, $2 = BOT_NAME（空でよい）→ 置換後を標準出力へ
render() {
  local c=$1
  local BOT_NAME=$2
  local k v
  c=${c//\{\{COMMON\}\}/$common}
  for k in $KEYS; do
    eval "v=\${$k-}"
    c=${c//\{\{$k\}\}/$v}
  done
  printf '%s\n' "$c"
}

mkdir -p "$REPO_PATH/bots" "$REPO_PATH/.github/ISSUE_TEMPLATE"

# ADR の雛形（無いときだけ置く。プロジェクトが育てる文書なので上書きしない）
if [ ! -f "$REPO_PATH/$ADR_DIR/0000-template.md" ]; then
  mkdir -p "$REPO_PATH/$ADR_DIR"
  cp "$here/shared/adr-template.md" "$REPO_PATH/$ADR_DIR/0000-template.md"
  echo "$ADR_DIR/0000-template.md（新規）"
fi

# 要件書の雛形（無いときだけ置く。Planner の計画ワーカーが章立てに使う）
if [ ! -f "$REPO_PATH/$REQ_DIR/0000-template.md" ]; then
  mkdir -p "$REPO_PATH/$REQ_DIR"
  cp "$here/shared/requirement-template.md" "$REPO_PATH/$REQ_DIR/0000-template.md"
  echo "$REQ_DIR/0000-template.md（新規）"
fi

# --- bot の指示文 ---
for f in "$here"/bots/*.md; do
  base=$(basename "$f")
  case "$base" in _*) continue ;; esac   # _common.md・_never.md は部品
  sed -n '1p' "$f" | grep -q '^<!-- BOT_NAME: .* -->$' || { echo "BOT_NAME の行が無い: $f" >&2; exit 1; }
  name=$(bot_name "${base%.md}")
  BOT_SLUG="${P}${base%.md}"
  body=$(sed '1d' "$f")
  render "$body" "$name" > "$REPO_PATH/bots/$base"
  echo "bots/$base  ($name)"
done

# --- Issue フォーム ---
for f in "$here"/github/ISSUE_TEMPLATE/*.yml.tmpl; do
  out="$REPO_PATH/.github/ISSUE_TEMPLATE/$(basename "${f%.tmpl}")"
  render "$(cat "$f")" "" > "$out"
  echo ".github/ISSUE_TEMPLATE/$(basename "${f%.tmpl}")"
done

# --- 手順書 ---
render "$(cat "$here/SETUP.md.tmpl")" "" > "$REPO_PATH/bots/SETUP.md"
echo "bots/SETUP.md"

echo
echo "展開先: $REPO_PATH"
echo "次は scripts/setup-github.sh $cfg"
echo "PMO は全チーム共通。チームを足したら scripts/render-pmo.sh --install <すべてのチームの team.*.config> を流す"
