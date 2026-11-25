#!/usr/bin/env bash
# GitHub 側の設定（ラベル・Project・ブランチ保護）を入れる。何度流しても同じ結果になる。
# 使い方: scripts/setup-github.sh <team.config>
set -euo pipefail

cfg=${1:?使い方: setup-github.sh <team.config> [--skip-protection]}
skip_protection=0
[ "${2-}" = "--skip-protection" ] && skip_protection=1
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
. "$cfg"

: "${REPO:?REPO が未設定}"
OWNER=${REPO%%/*}
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
REQUIRED_APPROVALS=${REQUIRED_APPROVALS:-0}
REQUIRED_CHECKS=${REQUIRED_CHECKS:-}

echo "== ラベル =="
while IFS=$'\t' read -r name color desc; do
  [ -n "${name:-}" ] || continue
  for k in LABEL_CONDUCTOR LABEL_FIXER LABEL_INCIDENT; do
    eval "v=\${$k-}"
    name=${name//\{\{$k\}\}/$v}
  done
  if gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" 2>/dev/null; then
    echo "  作成: $name"
  else
    gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null
    echo "  更新: $name"
  fi
done < "$here/github/labels.tsv"

echo
echo "== Project =="
if ! gh project list --owner "$OWNER" >/dev/null 2>&1; then
  cat <<'MSG'
  gh に project 権限が無いので Project の作成を飛ばす。
  次を実行してから、このスクリプトを流し直す（ブラウザ認証が開く）:

    gh auth refresh -s project

MSG
else
  num=$(gh project list --owner "$OWNER" --format json \
    | T="$PROJECT_TITLE" python3 -c 'import json,sys,os;d=json.load(sys.stdin);t=os.environ["T"];print(next((str(p["number"]) for p in d.get("projects",[]) if p["title"]==t),""))')
  if [ -z "$num" ]; then
    num=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["number"])')
    echo "  作成: #$num $PROJECT_TITLE"
  else
    echo "  既存: #$num $PROJECT_TITLE"
  fi
  gh project link "$num" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
    && echo "  リポジトリを連携: $REPO" || echo "  連携済みか、連携に失敗（画面で確認）"

  for fld in "担当 bot" "優先度"; do
    if ! gh project field-list "$num" --owner "$OWNER" --format json | grep -qF "\"$fld\""; then
      case "$fld" in
        "担当 bot") opts='Conductor,Fixer,Doc Keeper,Sentinel,人' ;;
        "優先度")   opts='P1,P2,P3' ;;
      esac
      gh project field-create "$num" --owner "$OWNER" --name "$fld" \
        --data-type SINGLE_SELECT --single-select-options "$opts" >/dev/null
      echo "  フィールド作成: $fld ($opts)"
    else
      echo "  フィールド既存: $fld"
    fi
  done

  # Status の選択肢。updateProjectV2Field は一覧を丸ごと置き換えるので、
  # item がすでに入っている Project では触らない（値が消える）
  st=$(gh project field-list "$num" --owner "$OWNER" --format json \
    | python3 -c 'import json,sys
fs=json.load(sys.stdin)["fields"]
f=next((x for x in fs if x["name"]=="Status"), None)
print("" if not f else f["id"]+" "+"|".join(o["name"] for o in f.get("options") or []))')
  st_id=${st%% *}
  st_opts=${st#* }
  if [ -z "$st_id" ]; then
    echo "  Status フィールドが見つからない（画面で確認する）"
  elif [ "${st_opts#*Ready}" != "$st_opts" ] && [ "${st_opts#*In review}" != "$st_opts" ]; then
    echo "  Status の選択肢は既に揃っている: $st_opts"
  else
    items=$(gh project item-list "$num" --owner "$OWNER" --format json \
      | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["items"]))')
    if [ "$items" != "0" ]; then
      echo "  Status に Ready / In review を足していないが、item が ${items} 件あるため触らない。"
      echo "  Project の画面で足す（API は選択肢を丸ごと置き換えるので値が消える）"
    else
      gh api graphql -f query='
mutation($id: ID!) {
  updateProjectV2Field(input: {
    fieldId: $id
    singleSelectOptions: [
      {name: "Todo",        color: GRAY,   description: "新規。Intake が整理し、人に着手の確認を出す"}
      {name: "Ready",       color: BLUE,   description: "人が着手を承認し、担当 bot のラベルが付いた"}
      {name: "In progress", color: YELLOW, description: "Fixer か Conductor が作業中"}
      {name: "In review",   color: ORANGE, description: "PR が開き、レビュー待ち"}
      {name: "Done",        color: GREEN,  description: "Issue のクローズ、または PR のマージ"}
    ]
  }) { projectV2Field { ... on ProjectV2SingleSelectField { name } } }
}' -F id="$st_id" >/dev/null \
        && echo "  Status の選択肢を Todo / Ready / In progress / In review / Done にした" \
        || echo "  Status の選択肢の更新に失敗（画面で足す）"
    fi
  fi

  echo "  未完了の issue を登録（Auto-add は有効化前の issue を拾わない）"
  gh issue list --repo "$REPO" --state open --limit 200 --json url \
    | python3 -c 'import json,sys;[print(i["url"]) for i in json.load(sys.stdin)]' \
    | while read -r url; do gh project item-add "$num" --owner "$OWNER" --url "$url" >/dev/null 2>&1 || true; done

  kind=$(gh api "users/$OWNER" --jq .type 2>/dev/null || echo User)
  case "$kind" in
    Organization) url="https://github.com/orgs/$OWNER/projects/$num" ;;
    *)            url="https://github.com/users/$OWNER/projects/$num" ;;
  esac
  CFG="$cfg" NUM="$num" URL="$url" python3 -c 'import os,re; p=os.environ["CFG"]; s=open(p,encoding="utf-8").read(); s=re.sub(r"(?m)^PROJECT_NUMBER=.*$","PROJECT_NUMBER="+os.environ["NUM"],s); s=re.sub(r"(?m)^PROJECT_URL=.*$","PROJECT_URL=\x27"+os.environ["URL"]+"\x27",s); open(p,"w",encoding="utf-8").write(s)'
  echo "  設定ファイルへ書き戻した: PROJECT_NUMBER=$num / $url"
  echo "  指示文に反映するには scripts/render.sh $cfg を流し直す"
fi

echo
echo "== ブランチ保護（${DEFAULT_BRANCH}）=="
if [ "$skip_protection" = "1" ]; then
  echo "  --skip-protection のため飛ばした。"
  echo "  入れると main への直接 push が塞がれ、マージはすべて PR 経由になる。"
  echo "  ローカルで --no-ff マージして push する運用をしている場合は、先にその運用を決める。"
  echo
  echo "完了（ブランチ保護を除く）。残りは bots/SETUP.md の手作業。"
  exit 0
fi
checks_json='null'
if [ -n "$REQUIRED_CHECKS" ]; then
  # orca/ で始まるものは bot が gh api で付ける commit status（GitHub App ではない）なので app_id -1（どこから付いてもよい）。
  # ほかは app_id を省く（GitHub が直近に付けた App を選ぶ）
  checks_json=$(CH="$REQUIRED_CHECKS" python3 -c 'import json,os;cs=[c.strip() for c in os.environ["CH"].split(",") if c.strip()];print(json.dumps({"strict":True,"checks":[dict(context=c,app_id=-1) if c.startswith("orca/") else dict(context=c) for c in cs]}))')
fi
body=$(A="$REQUIRED_APPROVALS" C="$checks_json" python3 - <<'PY'
import json, os
print(json.dumps({
  "required_status_checks": json.loads(os.environ["C"]),
  "enforce_admins": False,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": True,
    "require_code_owner_reviews": False,
    "required_approving_review_count": int(os.environ["A"]),
  },
  "restrictions": None,
  "required_conversation_resolution": True,
  "allow_force_pushes": False,
  "allow_deletions": False,
}))
PY
)
printf '%s' "$body" | gh api -X PUT "repos/$REPO/branches/$DEFAULT_BRANCH/protection" --input - >/dev/null \
  && echo "  設定した（PR 必須 / 強制 push 禁止 / 削除禁止 / 会話の解決必須 / 承認 $REQUIRED_APPROVALS 件）" \
  || echo "  失敗（非公開リポジトリのブランチ保護は有料プランが必要。画面で確認する）"

echo
echo "完了。残りは bots/SETUP.md の手作業。"
