#!/usr/bin/env bash
# 見回り: 誰にも拾われていない issue と PR を数える。
#   Intake の毎時の自動化が precheck に使い（拾うものが無ければ起動しない）、起動した Intake 本人が --list で中身を見る。
#   使い方: sweep.sh <owner/repo> [--list] [--stale-hours <時間>] [--grace-minutes <分>]
#   終了コード: 0 = 拾うものがある / 1 = 無い / 2 = 調べられなかった（gh の失敗など）
#
# 拾うもの（どれも GitHub のラベルとコメントだけで判定する。Orca の状態は見ない）
#   1. 未振り分けの issue: open で `triaged` も `needs-info` も付いていない
#   2. レビューの印が無い PR: open・下書きでない・最新のコミットの SHA を持つ `orca-review:` の印がコメントに無く、
#      最新のコミットから <分>（既定 60）以上たっている（作者の bot が push 後に自分で頼む再レビューと二重にしないため）。
#      ただし最新のコミットが既定ブランチの取り込み（「Merge branch '<既定ブランチ>'」、GitHub の Update branch）なら待たない
#      （作者の bot はそれを知らないので、誰も再レビューを頼まない。Reviewer は取り込みだけなら結果を引き継ぐ）
#   2'. セキュリティレビュー待ちの PR: 最新のコミットに `orca-review: <SHA> result=ok` の印があるのに、
#      `orca-security-review: <SHA>` の印が無く、レビューの印から <分> 以上たっている（Reviewer が Sentinel に頼む分と二重にしないため）
#   3. 止まっている担当: `triaged` と `bot:` ラベルがあり、`wait:human` も `needs-info` も無く、<時間> 以上更新が無い。
#      依存（GitHub の blocked by）が開いている issue は順番待ちなので数えない
#   4. 子 issue の無い要件: `requirement` が付いた open の issue で、マージ済みの計画 PR（本文に `作業 ID: req-<番号>`）があるのに sub-issue が 0 件
#   5. 子がすべて閉じた要件: `requirement` が付いた open の issue で、sub-issue が 1 件以上あり、すべて閉じている
#   4・5 は Planner に渡す（Intake が開発ルームの `@` で渡す）。`wait:human` の付いた要件は数えない
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo=${1:-}
case "$repo" in */*) shift ;; *) echo "使い方: sweep.sh <owner/repo> [--list] [--stale-hours <時間>] [--grace-minutes <分>]" >&2; exit 2 ;; esac
list=0; stale=24; grace=60
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list=1 ;;
    --stale-hours) stale=${2:?}; shift ;;
    --grace-minutes) grace=${2:?}; shift ;;
    *) echo "未知の引数: $1" >&2; exit 2 ;;
  esac
  shift
done

# issue は REST で取る（gh issue list には sub-issue と依存の集計が無い）。PR を除き、1 件 1 行の JSON にする
issues=$(gh api --paginate "repos/$repo/issues?state=open&per_page=100" \
  --jq '.[] | select(.pull_request == null) | {number, title, labels: [.labels[] | {name}], updatedAt: .updated_at, sub: .sub_issues_summary, dep: .issue_dependencies_summary}') || exit 2
prs=$(gh pr list -R "$repo" --state open --limit 100 --json number,title,headRefOid,isDraft,comments) || exit 2
merged=$(gh pr list -R "$repo" --state merged --limit 100 --json number,body) || exit 2

REPO="$repo" ISSUES="$issues" PRS="$prs" MERGED="$merged" LIST="$list" STALE="$stale" GRACE="$grace" python3 -I - <<'PY'
import json, os, re, subprocess, sys, datetime as dt
issues = [json.loads(l) for l in os.environ["ISSUES"].splitlines() if l.strip()]
prs = json.loads(os.environ["PRS"]); merged = json.loads(os.environ["MERGED"])
stale_h = float(os.environ["STALE"]); grace_m = float(os.environ["GRACE"]); show = os.environ["LIST"] == "1"
now = dt.datetime.now(dt.timezone.utc)
mark = re.compile(r"orca-review:\s*([0-9a-f]{7,40})(?:\s+result=(\w+))?")
smark = re.compile(r"orca-security-review:\s*([0-9a-f]{7,40})")

def labels(x): return {l["name"] for l in x.get("labels", [])}

_db = []
def default_branch():
    if not _db:
        r = subprocess.run(["gh", "repo", "view", os.environ["REPO"], "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"],
                           capture_output=True, text=True)
        if r.returncode != 0: sys.exit(2)
        _db.append(r.stdout.strip() or "main")
    return _db[0]

untriaged = [i for i in issues if not labels(i) & {"triaged", "needs-info"}]

unreviewed = []
unsecured = []
for p in prs:
    if p.get("isDraft"): continue
    sha = p["headRefOid"]
    seen = []
    for c in p.get("comments", []):
        for m, res in mark.findall(c.get("body", "")):
            seen.append((m, res, c.get("createdAt", "")))
    mine = [(res, at) for m, res, at in seen if sha.startswith(m)]
    if mine:
        if any(res == "ok" for res, _ in mine):
            done = any(sha.startswith(m) for c in p.get("comments", []) for m in smark.findall(c.get("body", "")))
            at = max(a for r, a in mine if r == "ok")
            mins = (now - dt.datetime.fromisoformat(at.replace("Z", "+00:00"))).total_seconds() / 60 if at else grace_m
            if not done and mins >= grace_m:
                unsecured.append(p)
        continue
    seen = [m for m, _, _ in seen]
    # 印の無い候補だけ、最新のコミットの日時を 1 件ずつ取る（pr list で commits を取ると GraphQL の上限を超える）
    r = subprocess.run(["gh", "api", f"repos/{os.environ['REPO']}/commits/{sha}", "--jq", "[.commit.committer.date, (.parents | length), .commit.message] | @json"],
                       capture_output=True, text=True)
    if r.returncode != 0: sys.exit(2)
    when, nparents, msg = json.loads(r.stdout.strip() or '["", 0, ""]')
    update = nparents == 2 and re.match(r"^Merge (remote-tracking )?branch '(origin/)?" + re.escape(default_branch()) + "'", msg or "")
    if when and not update:
        mins = (now - dt.datetime.fromisoformat(when.replace("Z", "+00:00"))).total_seconds() / 60
        if mins < grace_m: continue
    why = "印なし" if not seen else "古いコミットの印だけ"
    unreviewed.append((p, why + ("（既定ブランチの取り込み。結果の引き継ぎ候補）" if update else "")))

def blocked(i): return ((i.get("dep") or {}).get("blocked_by") or 0) > 0

stalled = []
for i in issues:
    ls = labels(i)
    if "triaged" not in ls or ls & {"wait:human", "needs-info"}: continue
    if blocked(i): continue
    owners = sorted(l for l in ls if l.startswith("bot:"))
    if not owners: continue
    age = (now - dt.datetime.fromisoformat(i["updatedAt"].replace("Z", "+00:00"))).total_seconds() / 3600
    if age >= stale_h: stalled.append((i, owners, age))

# 要件（Planner）: 計画 PR がマージ済みなのに子が無い / 子がすべて閉じた
planned = {}
for p in merged:
    for n in re.findall(r"作業 ID:\s*req-(\d+)", p.get("body") or ""):
        planned.setdefault(int(n), p["number"])
orphan, finished = [], []
for i in issues:
    ls = labels(i)
    if "requirement" not in ls or "wait:human" in ls: continue
    sub = i.get("sub") or {}
    total_sub, done_sub = sub.get("total") or 0, sub.get("completed") or 0
    if total_sub == 0 and i["number"] in planned: orphan.append((i, planned[i["number"]]))
    elif total_sub > 0 and done_sub == total_sub: finished.append((i, total_sub))

total = len(untriaged) + len(unreviewed) + len(unsecured) + len(stalled) + len(orphan) + len(finished)
if show:
    print(f"未振り分けの issue: {len(untriaged)}")
    for i in untriaged: print(f"  #{i['number']} {i['title']}")
    print(f"レビューの印が無い PR（最新のコミットから {grace_m:g} 分以上）: {len(unreviewed)}")
    for p, why in unreviewed: print(f"  #{p['number']} {p['headRefOid']} {why} {p['title']}")
    print(f"セキュリティレビュー待ちの PR（レビューは通過、{grace_m:g} 分以上）: {len(unsecured)}")
    for p in unsecured: print(f"  #{p['number']} {p['headRefOid']} {p['title']}")
    print(f"止まっている担当（{stale_h:g} 時間以上更新なし）: {len(stalled)}")
    for i, owners, age in stalled: print(f"  #{i['number']} {','.join(owners)} {age:.0f} 時間 {i['title']}")
    print(f"計画 PR がマージ済みなのに子 issue が無い要件: {len(orphan)}")
    for i, pr in orphan: print(f"  #{i['number']} 計画 PR #{pr} {i['title']}")
    print(f"子 issue がすべて閉じた要件: {len(finished)}")
    for i, n in finished: print(f"  #{i['number']} 子 {n} 件 {i['title']}")
sys.exit(0 if total else 1)
PY
