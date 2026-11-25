#!/usr/bin/env bash
# まとめて確かめる: シェルの構文、判定フックの試験、試しの設定でのレンダリング。
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
for f in "$here"/scripts/*.sh "$here"/tests/*.sh; do
  bash -n "$f" || { echo "NG 構文: $f"; fail=1; }
done
python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$here/scripts/bot-guard.py" || { echo "NG 構文: bot-guard.py"; fail=1; }
"$here/tests/bot-guard.sh" || fail=1
"$here/tests/render.sh" || fail=1
[ "$fail" -eq 0 ] && echo "すべて通った" || echo "失敗あり"
exit "$fail"
