#!/usr/bin/env python3
"""orca-team: bot の PreToolUse フック（確認を出さずに、決まりで禁じた操作だけを断る）。

Orca の bot は Approve for me（Claude Code の auto モード）か、セットアップ時の権限モードのまま続く会話で動く。
どちらでも、許可リストに当たらない操作（変数で包んだ orca の呼び出しなど）は分類器や人の確認に回り、作業が止まる。
このフックは全部の道具の呼び出しの前に動き、
  - 決まりで禁じた操作 → deny（人に聞かない。理由を bot に返すので、bot は別のやり方で続ける）
  - それ以外        → allow（確認を出さない）
を返す。人を待つ場面（設計の承認・マージ・凍結済みテスト・範囲外の判断）は bot の指示文で扱い、ここでは扱わない。

使い方（.claude/settings.json の hooks.PreToolUse から呼ぶ）:
  bot-guard.py --repo-path <人の手元のチェックアウト> --default-branch main --workspaces <ワーカーの作業場所> --bot-dir <bot のフォルダ>
  bot-guard.py --check '<Bash のコマンド>' …   … 判定だけを表示する（試験用）
フックが落ちたときは何も出さずに終わる（Claude Code の通常の判定に戻る）。
"""
import json, os, re, shlex, sys

HOME = os.path.expanduser("~")


def args():
    a = {"repo": "", "db": "main", "ws": "", "bot": "", "check": None, "tool": "Bash"}
    it = iter(sys.argv[1:])
    for k in it:
        if k == "--repo-path": a["repo"] = next(it)
        elif k == "--default-branch": a["db"] = next(it)
        elif k == "--workspaces": a["ws"] = next(it)
        elif k == "--bot-dir": a["bot"] = next(it)
        elif k == "--check": a["check"] = next(it)
        elif k == "--tool": a["tool"] = next(it)
    return a


A = args()
REPO = A["repo"].rstrip("/")
DB = A["db"]
WS = A["ws"].rstrip("/")
BOT = A["bot"].rstrip("/")

SECRET = re.compile(
    r"(/\.ssh/|/\.aws/|/\.codex/auth\.json|/\.config/gh/|/\.claude/\.credentials|\.netrc\b|/\.npmrc\b|/\.pypirc\b"
    r"|Library/Keychains|\bsecurity\s+(find|dump|export)-|\bgh\s+auth\s+token\b|RCW_TERMINAL_TOKEN)"
)


def expand(p):
    p = p.strip("'\"")
    if p.startswith("~"): p = HOME + p[1:]
    return p


def under(p, root):
    if not root or not p: return False
    p = os.path.normpath(expand(p))
    return p == root or p.startswith(root + "/")


def home_claude(p):
    """~/.claude/ の下（Claude Code が保存した長い出力 tool-results だけは読んでよい）"""
    p = os.path.normpath(expand(p))
    root = HOME + "/.claude"
    return (p == root or p.startswith(root + "/")) and "/tool-results/" not in p


def self_config(p):
    """bot が自分（や他の bot）の権限・指示文を書き換える経路"""
    p = os.path.normpath(expand(p))
    return bool(re.search(r"/\.claude/settings(\.local)?\.json$", p)) or bool(
        re.search(r"/\.orca/bots/[^/]+/(SOUL\.md|AGENTS\.md|CLAUDE\.md|bot\.json)$", p))


# ---------- Bash ----------

def normalize(cmd):
    c = cmd
    c = re.sub(r'"?\$\{ORCA_CLI_COMMAND(:-orca)?\}"?', "orca", c)
    c = re.sub(r'"?\$ORCA_CLI_COMMAND\b"?', "orca", c)
    for m in re.finditer(r"\b([A-Za-z_]\w*)=(['\"]?)(orca|/usr/local/bin/orca)\2(?=[\s;&|]|$)", c):
        v = re.escape(m.group(1))
        c = re.sub(r'"?\$\{?' + v + r'\}?"?(?=[\s;&|)]|$)', "orca", c)
    c = re.sub(r"(?<![\w/])/usr/local/bin/orca\b", "orca", c)
    return c


def segments(c):
    return [s.strip() for s in re.split(r"&&|\|\||;|\||\n|\$\(|`|\(|\)", c) if s.strip()]


def words(seg):
    try:
        w = shlex.split(seg, posix=True)
    except ValueError:
        w = seg.split()
    # 先頭の環境変数の代入と前置き（command / exec / time / nohup / env）を落とす
    while w and (re.match(r"^[A-Za-z_]\w*=", w[0]) or w[0] in ("command", "exec", "time", "nohup", "env")):
        w = w[1:]
    return w


GIT_WRITE = {"checkout", "switch", "reset", "clean", "merge", "rebase", "pull", "stash", "commit", "add", "rm", "mv",
             "restore", "cherry-pick", "revert", "am", "apply", "worktree", "submodule", "tag", "update-ref", "gc", "prune"}


def api_fields(t):
    """gh api の引数 → (位置引数, -f/-F のフィールド)。-X・--input などの知らない旗があれば None"""
    skip = {"-f", "-F", "--field", "--raw-field", "-H", "--header", "--jq", "-q", "--template", "-t", "--hostname", "-p", "--preview", "--cache"}
    pos, fields, i = [], [], 0
    while i < len(t):
        x = t[i]
        if x in skip:
            if x in ("-f", "-F", "--field", "--raw-field") and i + 1 < len(t): fields.append(t[i + 1])
            i += 2; continue
        if x.startswith("-"): return None  # -X・--input などは認めない
        pos.append(x); i += 1
    return pos, fields


def allowed_write(t):
    """bot が gh api で書いてよいのは次の 3 つだけ（ほかのフィールドを付けないもの）。
    1. 自分の commit status（context が orca/ で始まるもの）
       gh api repos/<owner>/<repo>/statuses/<SHA> -f state=success -f context=orca/security-review -f description=…
    2. 要件の issue に子 issue を足す（Planner。GitHub の sub-issue）
       gh api repos/<owner>/<repo>/issues/<番号>/sub_issues -F sub_issue_id=<子の id>
    3. 子 issue に依存を張る（Planner。GitHub の blocked by）
       gh api repos/<owner>/<repo>/issues/<番号>/dependencies/blocked_by -F issue_id=<依存先の id>"""
    r = api_fields(t)
    if not r: return False
    pos, fields = r
    if len(pos) != 1: return False
    if any("=" not in f for f in fields): return False
    kv = dict(f.split("=", 1) for f in fields)
    if len(kv) != len(fields): return False  # 同じ名前を 2 回付けない
    path = pos[0]
    if re.match(r"^/?repos/[^/]+/[^/]+/statuses/[0-9a-f]{7,40}$", path):
        return set(kv) <= {"state", "context", "description", "target_url"} and kv.get("context", "").startswith("orca/") \
            and kv.get("state") in ("success", "failure", "pending", "error")
    if re.match(r"^/?repos/[^/]+/[^/]+/issues/[0-9]+/sub_issues$", path):
        return set(kv) == {"sub_issue_id"} and kv["sub_issue_id"].isdigit()
    if re.match(r"^/?repos/[^/]+/[^/]+/issues/[0-9]+/dependencies/blocked_by$", path):
        return set(kv) == {"issue_id"} and kv["issue_id"].isdigit()
    return False


def bash_reason(cmd):
    c = normalize(cmd)
    if SECRET.search(c):
        return "秘密（鍵・トークン・資格情報）の置き場所に触れる操作は禁じられています。"
    if re.search(r"(^|[\s'\"=])(~|" + re.escape(HOME) + r")/\.claude(/|\s|$)", c) and "/tool-results/" not in c:
        return "~/.claude の下は読まない・書かない決まりです（Claude Code が保存した tool-results だけは読めます）。"
    cwd = None
    for seg in segments(c):
        w = words(seg)
        if not w: continue
        prog = os.path.basename(w[0])
        rest = " ".join(w[1:])
        if prog == "cd":
            cwd = expand(w[1]) if len(w) > 1 else HOME
            continue
        if prog == "sudo":
            return "sudo は使えません。"
        # --- git ---
        if prog == "git":
            gdir, i = cwd, 1
            while i < len(w) and w[i].startswith("-"):
                if w[i] == "-C" and i + 1 < len(w): gdir = expand(w[i + 1]); i += 2; continue
                if w[i] == "-c" and i + 1 < len(w): i += 2; continue
                i += 1
            sub = w[i] if i < len(w) else ""
            a = w[i + 1:]
            if sub == "push":
                if any(x in ("--force", "-f", "--force-with-lease", "--mirror", "--all", "--prune") or x.startswith("--force") for x in a) \
                        or any(x.startswith("+") for x in a):
                    return "強制 push は禁じられています。新しいコミットを足して push してください。"
                if any(x in ("--delete", "-d") for x in a) or any(x.startswith(":") for x in a):
                    return "リモートのブランチの削除は禁じられています（消すかどうかは人が決めます）。"
                refs = [x for x in a if not x.startswith("-")]
                if any(x == DB or x.endswith(":" + DB) or x.endswith(":refs/heads/" + DB) or x == "refs/heads/" + DB for x in refs[1:]):
                    return f"{DB} への push は禁じられています。作業ブランチに push して PR を作ってください。"
            if sub == "branch" and any(x in ("-D", "--delete", "-d") for x in a):
                return "ブランチの削除は禁じられています。"
            if under(gdir or "", REPO) and sub in GIT_WRITE:
                return f"{REPO} は人の手元のチェックアウトです。git {sub} でここを変えないでください。変更はワーカーに自分の作業場所で任せてください（共通の決まり「コードと文書の変え方」）。"
            continue
        # --- gh ---
        if prog == "gh":
            s = w[1:3]
            if s[:2] == ["pr", "merge"]:
                return "PR のマージは人が決めます。マージを頼むときは人に確認を出してください。"
            if s[:2] == ["pr", "review"] and any(x in ("--approve", "-a") or x.startswith("--approve") for x in w[3:]):
                return "PR の承認はしない決まりです。レビューの結果はコメントで残してください。"
            if s[:1] == ["api"]:
                t = w[2:]
                if any(x in ("-X", "--method") for x in t) or any(re.match(r"^(-X|--method=)", x) for x in t):
                    m = re.search(r"(?:-X|--method)[=\s]*(\w+)", rest)
                    if not m or m.group(1).upper() != "GET":
                        return "gh api での書き込み（-X / --method）は禁じられています。gh issue / gh pr / gh project のコマンドを使ってください。"
                if re.search(r"merge", rest, re.I):
                    return "gh api でのマージ（merge を含む呼び出し）は禁じられています。"
                if re.search(r"\bmutation\b", rest):
                    return "gh api graphql の mutation は禁じられています（読むだけにしてください）。"
                if "graphql" not in t and any(x in ("-f", "-F", "--field", "--raw-field", "--input") for x in t) and not allowed_write(t):
                    return "gh api の REST にフィールドを付けると書き込み（POST）になるので禁じられています。"
            if s[:1] == ["release"] and len(s) > 1 and s[1] in ("create", "edit", "upload", "delete", "delete-asset"):
                return "リリースは人が決めます。"
            if s[:1] == ["repo"] and len(s) > 1 and s[1] in ("edit", "delete", "archive", "unarchive", "rename", "create", "fork", "sync", "set-default"):
                return "リポジトリの設定は変えない決まりです。"
            if s[:1] in (["secret"], ["variable"]) and len(s) > 1 and s[1] != "list":
                return "秘密と変数は変えない決まりです。"
            if s[:1] == ["auth"] and len(s) > 1 and s[1] != "status":
                return "gh の認証は触らない決まりです。"
            if s[:2] in (["issue", "delete"], ["label", "delete"], ["gist", "create"], ["extension", "install"], ["cache", "delete"]):
                return f"gh {' '.join(s[:2])} は禁じられています。"
            if s[:1] == ["workflow"] and len(s) > 1 and s[1] in ("run", "disable", "enable"):
                return "ワークフローの起動・停止は人が決めます（デプロイにつながることがあるため）。"
            continue
        # --- orca ---
        if prog == "orca":
            s = w[1:4]
            if s[:1] == ["automations"] and len(s) > 1 and s[1] in ("create", "edit", "remove", "run"):
                return "Orca の自動化は人が入れます。待ち（--once）も作らないでください。受け渡しは開発ルームの返事に `@名前`、取りこぼしは Intake の見回りが拾います。"
            if s[:2] == ["orchestration", "send"]:
                t = w[3:]
                to = [t[i + 1] for i, x in enumerate(t[:-1]) if x == "--to"] + [x.split("=", 1)[1] for x in t if x.startswith("--to=")]
                if any(x.startswith("bot:") for x in to):
                    return ("bot へのメール（--to bot:…）は使わない決まりです（2026-11-25 から）。開発ルームにいるなら返事の最後に "
                            "`@<相手の名前> <issue / PR の番号> <してほしいこと>` と書いてください。ルームの外にいるなら、その issue / PR に "
                            "`@orca-bots <相手の役割>` を付けたコメントで渡してください。自分の Run のワーカー（--to dispatch:… など）へは送れます。")
            if s[:2] == ["worktree", "rm"]:
                t = w[3:]
                if any(x.startswith("--force") for x in t) or ".." in rest:
                    return "作業場所を --force や .. で消すのは禁じられています。"
                paths = [x.split("path:", 1)[1] for x in t if x.startswith("path:")]
                if not paths or not all(under(p, WS) for p in paths):
                    return f"消してよい作業場所は {WS} の下だけです（--worktree path:<そのパス> で指定してください）。"
            if s[:1] in (["account"], ["plugin"], ["host"], ["open"], ["serve"]) or s[:2] in (
                    ["environment", "add"], ["environment", "rm"], ["skills", "install"], ["skills", "share"], ["skills", "update"],
                    ["bot", "create"], ["bot", "import"], ["bot", "tools"], ["bot", "google-setup"], ["bot", "composio"]):
                return f"orca {' '.join(s[:2])} は Orca 本体の設定を変えるので、bot からは使えません。"
            continue
        # --- 外への送信 ---
        if prog in ("ssh", "scp", "sftp", "nc", "ncat", "netcat", "telnet", "ftp"):
            return f"{prog} で外へ接続するのは禁じられています。"
        if prog == "rsync" and any(re.match(r"^[^/\s]+:", x) for x in w[1:]):
            return "rsync で外へ送るのは禁じられています。"
        if prog == "curl" and (re.search(r"(^|\s)(-d|--data\S*|-F|--form\S*|-T|--upload-file|--json)(\s|=|$)", rest)
                               or re.search(r"(-X|--request)[=\s]*(POST|PUT|PATCH|DELETE)", rest, re.I)):
            return "curl での送信（POST などのデータ付き）は禁じられています。GitHub への書き込みは gh のコマンドを使ってください。"
        if prog == "wget" and re.search(r"--post|--method", rest):
            return "wget での送信は禁じられています。"
        if prog in ("printenv",) or (prog == "env" and len(w) == 1):
            return "環境変数をまとめて出すのは禁じられています（トークンが入っていることがあるため）。"
        # --- 人の手元のチェックアウトと、自分の権限・指示文への書き込み ---
        targets = []
        targets += re.findall(r"(?<![<\d&])>>?\s*([^\s;&|]+)", seg)
        if prog in ("cp", "mv", "install", "ln") and len(w) > 2: targets.append(w[-1])
        if prog in ("tee", "touch", "mkdir", "rm", "rmdir", "truncate", "chmod", "chown"): targets += [x for x in w[1:] if not x.startswith("-")]
        if prog in ("sed", "perl") and any(x.startswith("-i") or x == "-pi" for x in w[1:]): targets += [x for x in w[1:] if not x.startswith("-")]
        if prog in ("npm", "pnpm", "yarn") and len(w) > 1 and w[1] in ("install", "i", "add", "remove", "rm", "update", "up", "ci", "uninstall"):
            d = cwd
            for k, x in enumerate(w):
                if x in ("-C", "--dir", "--prefix") and k + 1 < len(w): d = expand(w[k + 1])
            if under(d or "", REPO):
                return f"{REPO}（人の手元）で依存を入れ替えないでください。ワーカーに任せてください。"
        for t in targets:
            t = expand(t)
            full = t if t.startswith("/") else os.path.join(cwd, t) if cwd else t
            if full.startswith("/dev/"): continue
            if under(full, REPO):
                return f"{REPO} は人の手元のチェックアウトです。ここのファイルを書き換えないでください。変更はワーカーに任せてください。"
            if self_config(full):
                return "bot の権限（.claude/settings.json）と指示文（SOUL.md など）は人が入れます。書き換えないでください。"
        if prog == "rm" and any(re.match(r"^-\w*[rR]", x) or x == "--recursive" for x in w[1:]):
            for t in [x for x in w[1:] if not x.startswith("-")]:
                full = os.path.normpath(expand(t) if expand(t).startswith("/") else os.path.join(cwd or os.getcwd(), expand(t)))
                if not re.match(r"^(/tmp/|/private/tmp/|/var/folders/)", full + "/") and not under(full, BOT):
                    return "一時フォルダと自分のフォルダの外を rm -r で消すのは禁じられています。"
    return None


def path_reason(tool, inp):
    p = inp.get("file_path") or inp.get("notebook_path") or inp.get("path") or ""
    if not p: return None
    if SECRET.search(p):
        return "秘密（鍵・トークン・資格情報）の置き場所は読まない・書かない決まりです。"
    if home_claude(p):
        return "~/.claude の下は読まない・書かない決まりです（tool-results だけは読めます）。"
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        if under(p, REPO):
            return f"{REPO} は人の手元のチェックアウトです。ここのファイルを書き換えないでください。変更はワーカーに任せてください。"
        if self_config(p):
            return "bot の権限（.claude/settings.json）と指示文（SOUL.md など）は人が入れます。書き換えないでください。"
    return None


def decide(tool, inp):
    if tool == "Bash":
        return bash_reason(inp.get("command", ""))
    return path_reason(tool, inp)


def out(reason):
    d = {"hookEventName": "PreToolUse"}
    if reason:
        d.update(permissionDecision="deny", permissionDecisionReason="[orca-team の決まり] " + reason)
    else:
        d.update(permissionDecision="allow", permissionDecisionReason="orca-team bot-guard: 決まりに当たらないので確認なしで通す")
    return json.dumps({"hookSpecificOutput": d}, ensure_ascii=False)


if __name__ == "__main__":
    if A["check"] is not None:
        r = decide(A["tool"], {"command": A["check"], "file_path": A["check"]})
        print("deny: " + r if r else "allow")
        sys.exit(0)
    try:
        ev = json.load(sys.stdin)
        print(out(decide(ev.get("tool_name", ""), ev.get("tool_input") or {})))
    except Exception:
        sys.exit(0)  # 何も出さない → Claude Code の通常の判定に戻る
