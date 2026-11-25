#!/usr/bin/env bash
# 試しの設定でレンダリングして、置き換え残し（{{KEY}}）が無いことを確かめる。
# 一時フォルダに架空のリポジトリを作って render.sh と render-pmo.sh（--install なし）を流す。Orca と GitHub には触らない。
# render.sh は bash 3.2 の文字列置換で 1〜2 分かかる。
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/orca-team-test.XXXXXX")" && pwd)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/app" "$tmp/configs"
bad=0

# 設定は 2 チーム分作る（略号なしと ml）。render.sh は遅いので略号なしだけ流し、PMO の表は 2 チームで確かめる
for code in '' ml; do
  sed -e "s|^REPO=.*|REPO='owner/app'|" -e "s|^REPO_PATH=.*|REPO_PATH='$tmp/app'|" -e "s|^TEAM_CODE=.*|TEAM_CODE='$code'|" \
    "$here/team.config.example" > "$tmp/configs/team.app${code:+-$code}.config"
done
for code in ''; do
  cfg="$tmp/configs/team.app${code:+-$code}.config"
  "$here/scripts/render.sh" "$cfg" > /dev/null
  left=$(grep -rl '{{[A-Z_]*}}' "$tmp/app/bots" "$tmp/app/.github" || true)
  if [ -n "$left" ]; then bad=$((bad+1)); echo "NG 置き換え残し（TEAM_CODE='$code'）:"; grep -rn '{{[A-Z_]*}}' $left | head; fi
  grep -qF "$cfg" "$tmp/app/bots/SETUP.md" || { bad=$((bad+1)); echo "NG SETUP.md に設定ファイルのパスが無い（TEAM_CODE='$code'）"; }
  grep -qF "$here/scripts/" "$tmp/app/bots/SETUP.md" || { bad=$((bad+1)); echo "NG SETUP.md にテンプレートのパスが無い（TEAM_CODE='$code'）"; }
done

pmo=$("$here/scripts/render-pmo.sh" "$tmp"/configs/team.*.config)
case "$pmo" in *'{{'*) bad=$((bad+1)); echo "NG PMO の指示文に置き換え残し" ;; esac
[ "$(printf '%s\n' "$pmo" | grep -c '`owner/app`')" -eq 2 ] || { bad=$((bad+1)); echo "NG PMO の表にチームが 2 行ない"; }
"$here/scripts/render-pmo.sh" > /dev/null 2>&1 && { bad=$((bad+1)); echo "NG render-pmo.sh が設定ファイルなしで通った"; }

echo "レンダリングの試験: 期待と違う $bad 件"
[ "$bad" -eq 0 ]
