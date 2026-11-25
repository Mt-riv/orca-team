#!/usr/bin/env bash
# render.sh で展開した <REPO_PATH>/bots/<役割>.md の「SOUL.md 本文」を、各 bot の ~/.orca/bots/<フォルダ>/SOUL.md に入れる。
# 末尾の `## Never` の節は bots/_never.md（チームの禁止事項）に置き換える。Orca が作成時に入れる既定の Never
# 「オーナーが許すまで何も変えない（コメント・ラベル・PR）」が残ると、bot は読んで報告するだけで止まるため。
#   使い方: install-souls.sh <team.config> [役割のスラッグ…]（役割を省くと PMO 以外の 10 体）
# 既存の SOUL.md は SOUL.md.bak を残して置き換える。中身が同じなら書かない。
set -euo pipefail
cfg=${1:?使い方: install-souls.sh <team.config> [役割…]}; shift
# shellcheck disable=SC1090
. "$cfg"
here=$(cd "$(dirname "$0")/.." && pwd)
TEAM_CODE=${TEAM_CODE-}
P=${TEAM_CODE:+${TEAM_CODE}-}
. "$here/scripts/names.sh"
roles=${*:-reviewer ci-guardian intake fixer doc-keeper conductor sentinel release-captain ops-scribe planner}
never=$(sed -e "s|{{DEFAULT_BRANCH}}|${DEFAULT_BRANCH:-main}|g" -e "s|{{REPO}}|$REPO|g" "$here/bots/_never.md")

for r in $roles; do
  NAME=$(bot_name "$r") SRC="$REPO_PATH/bots/$r.md" NEVER="$never" python3 - <<'PY'
import glob, json, os, shutil, sys
name, src, never = os.environ["NAME"], os.environ["SRC"], os.environ["NEVER"].rstrip("\n")
hits = [os.path.dirname(p) for p in glob.glob(os.path.expanduser("~/.orca/bots/*/bot.json"))
        if json.load(open(p)).get("name") == name]
if len(hits) != 1:
    sys.exit(f"bot が {len(hits)} 件見つかった: {name}")
lines = open(src).read().split("\n")
i = lines.index("## SOUL.md 本文")
j = next(k for k in range(i + 1, len(lines)) if lines[k].startswith("```markdown"))
end = next(k for k in range(j + 1, len(lines)) if lines[k].startswith("## オートメーション依頼文"))
body = lines[j + 1:end]
while body and not body[-1].strip(): body.pop()
if not body or body[-1].strip() != "```":
    sys.exit(f"SOUL.md 本文の閉じ ``` が見つからない: {src}")
body.pop()
while body and not body[-1].strip(): body.pop()
new = "\n".join(body) + "\n\n" + never + "\n"
soul = os.path.join(hits[0], "SOUL.md")
cur = open(soul).read() if os.path.exists(soul) else ""
if new == cur:
    print(f"変化なし: {name}"); sys.exit(0)
if cur: shutil.copy(soul, soul + ".bak")
open(soul, "w").write(new)
print(f"書き換え: {name} → {soul}")
PY
done
