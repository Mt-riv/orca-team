#!/usr/bin/env bash
# チームの 10 体の自動化（定時スケジュールと GitHub イベント起動）を Orca に作る。
# PMO は全チーム共通なので、その自動化は scripts/render-pmo.sh --install が作る。
# どの自動化も開発ルーム（ROOM_DEV）の中で動かす（--runs-in chat:<その bot のルームの会話>）。依頼文はオーナーの書き込みとしてルームに出て、
# bot の返事もルームに出る。bot は返事の `@名前` で次の bot に渡す（2026-11-25 から。メールは使わない）。
#   使い方: setup-automations.sh <team.config>
# 前提: bot が画面で作成済みで、イベント起動を持つ bot に GitHub コネクタが付いていること。
#       コネクタが無い bot のイベント起動は Orca が拒否する（その行だけ NG と出て、他は続ける）。
#       10 体が ROOM_DEV のメンバーであること。メンバーでない bot の自動化は、ルームの外（毎回新しい会話）で動かし、警告を出す。
# 同じ名前の自動化が既にあれば作らず、依頼文と precheck だけを今の版に合わせる（何度流してもよい）。
# 時刻は bots/*.md の依頼文と SETUP.md の時刻表に合わせてある。変えるときは 3 か所を揃える。
set -euo pipefail
cfg=${1:?使い方: setup-automations.sh <team.config>}
# shellcheck disable=SC1090
. "$cfg"
TIMEZONE=${TIMEZONE:-Asia/Tokyo}
R=$REPO
here=$(cd "$(dirname "$0")/.." && pwd)
TEAM_CODE=${TEAM_CODE-}
P=${TEAM_CODE:+${TEAM_CODE}-}
. "$here/scripts/names.sh"

ROOM_DEV=${ROOM_DEV:-}
[ -n "$ROOM_DEV" ] || ROOM_DEV=$(room_name dev)

# bot 名 → 開発ルームの中のその bot の会話 ID（bot-group-member-…）。見つからなければ空
room_chat() {
  orca bot chats --bot "$1" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("result") or {}
for c in (r.get("chats") if isinstance(r,dict) else r) or []:
    if c.get("title")==sys.argv[1] and str(c.get("id","")).startswith("bot-group-member-"): print(c["id"]); break' "$ROOM_DEV"
}
# room_args <bot> … ルームで動かすための引数（--runs-in chat:… --results-to chat）を配列 RA に入れる
room_args() {
  local c; c=$(room_chat "$1")
  if [ -n "$c" ]; then RA=(--runs-in "chat:$c" --results-to chat)
  else RA=(); echo "警告: $1 は「$ROOM_DEV」のメンバーではないので、ルームの外で動かします（Orca の画面でルームに入れてから流し直してください）" >&2; fi
}

# 名前 → id（既にあれば作らずに文面と precheck とルームを今の版に合わせる）
existing=$(orca automations list --json | python3 -c 'import json,sys; print("\n".join(a["name"]+"\t"+a["id"] for a in json.load(sys.stdin).get("result",{}).get("automations",[])))')

report() { python3 -c 'import json,sys; d=json.load(sys.stdin); n=sys.argv[1]; v=sys.argv[2]; print((v+": " if d.get("ok") else "NG:   ")+n+("" if d.get("ok") else "  "+d.get("error",{}).get("message","")))' "$1" "$2"; }

# mk <bot> <名前> <依頼文> <precheck（空なら無し）> <作成の引数…>
mk() {
  local bot=$1 name=$2 prompt=$3 pre=$4; shift 4
  local id; local -a P=()
  room_args "$bot"
  [ -n "$pre" ] && P=(--precheck "$pre")
  id=$(printf '%s\n' "$existing" | awk -F '\t' -v n="$name" '$1==n {print $2; exit}')
  if [ -n "$id" ]; then
    orca automations edit "$id" --prompt "$prompt" ${P[@]+"${P[@]}"} ${RA[@]+"${RA[@]}"} --json | report "$name" "更新" || true
    return 0
  fi
  orca automations create --name "$name" "$@" --prompt "$prompt" ${P[@]+"${P[@]}"} ${RA[@]+"${RA[@]}"} --enabled --json | report "$name" "作成" || true
}
sched() { # <bot> <name> <rrule か cron> <prompt> [precheck]
  mk "$1" "$2" "$4" "${5:-}" --bot "$1" --trigger "$3" --timezone "$TIMEZONE"
}
event() { # <bot> <name> <on> <prompt>
  mk "$1" "$2" "$4" "" --bot "$1" --on "$3"
}
off() { # <name> … あれば止める（消さない）
  local id
  id=$(printf '%s\n' "$existing" | awk -F '\t' -v n="$1" '$1==n {print $2; exit}')
  [ -n "$id" ] || { echo "無し: $1"; return 0; }
  orca automations edit "$id" --disabled --json | report "$1" "停止" || true
}

echo "== 定時（${TIMEZONE}）=="
sched "$(bot_name release-captain)" "$(bot_name release-captain): 平日の朝" "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=8;BYMINUTE=30" \
  "SOUL.md の「やること（平日の朝・依頼時）」を実行してください。リリースノートは書かないでください。"
sched "$(bot_name ci-guardian)" "$(bot_name ci-guardian): 月曜の定時" "FREQ=WEEKLY;BYDAY=MO;BYHOUR=9;BYMINUTE=30" \
  "SOUL.md の「月曜の定時」を実行してください。"
sched "$(bot_name sentinel)" "$(bot_name sentinel): 月曜の定時" "FREQ=WEEKLY;BYDAY=MO;BYHOUR=10;BYMINUTE=0" \
  "SOUL.md の「月曜の定時」を実行してください。"
sched "$(bot_name doc-keeper)" "$(bot_name doc-keeper): 水曜の定時" "FREQ=WEEKLY;BYDAY=WE;BYHOUR=10;BYMINUTE=0" \
  "SOUL.md の「やること（水曜の定時）」を実行してください。"
sched "$(bot_name ops-scribe)" "$(bot_name ops-scribe): 金曜の引き継ぎ" "FREQ=WEEKLY;BYDAY=FR;BYHOUR=16;BYMINUTE=0" \
  "SOUL.md の「金曜の引き継ぎ」を実行してください。"
# 見回り: 毎時 15 分（7〜23 時）。precheck（sweep.sh）が拾うものを見つけたときだけ会話が始まる
# RRULE の BYHOUR は 1 つしか受け付けない（2026-11-23 確認）ので cron で書く
sched "$(bot_name intake)" "$(bot_name intake): 見回り" "15 7-23 * * *" \
  "SOUL.md の「やること（毎時の見回り）」を実行してください。拾うものが無ければ 1 行で終えてください。" \
  "$here/scripts/sweep.sh $R"

echo "== GitHub イベント（${R}）=="
# オーナーの操作（ラベル・issue・コメント）では発火しない。bot もオーナー名義なので、bot が立てた issue・付けたラベルでも発火しない。
# bot の操作でも発火するのは、マージ・close・conflict・CI の結果だけ（trigger-options の説明）。
# bot 同士は開発ルームの返事の `@名前` で渡す。人が頼むときはルームで `@名前`、GitHub では issue で @orca-bots <bot> とメンションする。
# 協働者が立てた issue は Intake の issue_opened で拾い、振り分けは Intake がルームの `@` で渡す。
event "$(bot_name reviewer)" "$(bot_name reviewer): PR が開かれたとき" "github.pr_opened in=${R} from=me" \
  "開かれた PR について、SOUL.md の手順でレビューし、結果と印（orca-review）を PR に残して（gh pr comment）、直すべき点の受け渡しまで行ってください。"
event "$(bot_name ci-guardian)" "$(bot_name ci-guardian): check 失敗" "github.ci_failed in=${R}" \
  "落ちた check について、SOUL.md の「やること」を始めてください。"
event "$(bot_name intake)" "$(bot_name intake): issue が立ったとき" "github.issue_opened in=${R}" \
  "立った issue について、SOUL.md の「やること（issue ごと）」を始めてください。"
event "$(bot_name conductor)" "$(bot_name conductor): PR マージ時" "github.pr_merged in=${R}" \
  "マージされた PR について、SOUL.md の「完了後の片付け」を実行してください。A は自分の Run の PR のときだけ、B（ほかの bot の作業場所）と C（次の issue）はどの PR でも行ってください。"
event "$(bot_name sentinel)" "$(bot_name sentinel): PR マージ時" "github.pr_merged in=${R}" \
  "マージされた PR について、SOUL.md の「やること（PR マージ時。後追いの検査）」を実行してください。マージ前のセキュリティレビューを通っていれば何もせずに終えてください。"

# Planner: 自分の計画 PR のマージで子 issue を立て、close で止まる。contains= で名前を含む PR に絞る（本文に効かなくても見回りが拾う）
event "$(bot_name planner)" "$(bot_name planner): 計画 PR のマージ" "github.pr_merged in=${R} contains=\"$(bot_name planner)\"" \
  "マージされた PR が自分の計画 PR（題名が [$(bot_name planner)]、本文に 作業 ID: req-）なら、SOUL.md の「やること（計画 PR がマージされたら）」を実行してください。違えば 1 行で終えてください。"
event "$(bot_name planner)" "$(bot_name planner): 計画 PR の close" "github.pr_closed in=${R} contains=\"$(bot_name planner)\"" \
  "閉じられた PR が自分の計画 PR なら、SOUL.md の「やること（計画 PR が閉じられたら）」を実行してください。違えば 1 行で終えてください。"

echo "== ラベルの起動（止める）=="
# Intake が担当ラベルを付けると、ラベルの起動と Intake の受け渡しで同じ bot が 2 回起きる（2026-11-23、#14 #15 で Fixer が 3 会話）。
# オーナー名義でもラベルの起動は発火した（trigger-options の説明と違う）。受け渡しは Intake の `@` に一本化し、ラベルの起動は止める。
off "$(bot_name fixer): ${LABEL_FIXER} ラベル"
off "$(bot_name conductor): ${LABEL_CONDUCTOR} ラベル"
off "$(bot_name ops-scribe): ${LABEL_INCIDENT} ラベル"
