# 設計書と実機（Orca v1.4.269）のずれ

2026-11-22 に `orca --help` と `orca skills get orchestration --full` を読んで確認した結果。
設計書（Orca Bots チーム設計提案。非公開）のうち、
そのままでは動かない箇所と、テンプレートでどう直したか。

2026-11-23 以降の観察は、最初の展開先（remote-code-watch、略して rcw。非公開リポジトリ）での記録。
`#<番号>`・`rcw#<番号>` はそのリポジトリの issue / PR を指す。

## 直したもの

| 設計書の記述 | 実機 | テンプレートでの扱い |
| --- | --- | --- |
| `orca orchestration gate-create --task ... --question ...` で設計ゲートを付ける | **そのコマンドは無い。** `decision_gate` は Dispatch が送るメッセージ**種別**で、作る CLI は無い（`orchestration` の節に gate-create は存在しない） | Conductor が**人に確認を出してそこで止まる**形にした。承認が返るまで実装ワーカーを起動しない |
| `orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000` で待つ | 公式スキルが明確に禁止している。「ポーリングや watch スクリプトを書くな。スクリプトの `check` が自分の受信箱を取るので、Orca が起こせなくなる」 | ワーカーを起動したら**ターンを終える**。Orca が起こしたときに処理する、という書き方にした |
| コマンド例に `--environment` が無い | `run-create` / `task-create` / `task-list` / `worker-list` / `worker-start` に `--environment local` を付けないと、同じ Orca に届かないことがある | すべての例に `--environment local` を入れた |
| （記述なし） | 複数行の文をヒアドキュメント（`<<`）で渡すとシェルが止まることがある。`--spec-file` / `--body-file` を使う | Conductor の手順に明記した |
| （記述なし） | 並列起動は 1 回のシェルコマンドで**4 体程度まで**。別々のツール呼び出しは直列になる | 並列起動の雛形をそのまま入れた |
| 指示文を「bot の最初のチャットに貼る」 | `~/.orca/bots/<id>/SOUL.md` が「何者で、どう働くか」の正。AGENTS.md が「SOUL.md はオーナーが頼んだときだけ変える」と書いている（= オーナーは書いてよい） | SOUL.md 本文は**ファイルに直接書く**。オートメーション依頼文だけチャットに貼る |

## 設計書どおりで確認できたもの

- bot の作成・権限設定・コネクタ接続を**人の側から**行う CLI は無い。`orca bot create --offer` はあるが
  「bot のチャットから実行する」制約があり（外から叩くと `Run this from a bot's chat.`）、カードを人が押して初めて作られる。
  bot 本体・権限・コネクタ・ルームは画面で作る（2026-11-23 に Orca Computer Use で自動化した。下の節）。
- `bot.json` に `members` がある（グループルームのメンバー）。ルームは bot の一種として作られる。
- `orca skills list` に `orca-cli` と `orchestration` が入っている。`orca skills install` で導入する。
- `worker-start` の `--worktree new-child --name <name> --setup run`、`worker-release --dispatch <id>`、
  `send --to dispatch:<id>`、`reply --id <msg_id>` は実在する。

## 環境側の不足（2026-11-22 時点）

| 項目 | 状態 | 影響 |
| --- | --- | --- |
| 常駐 Orca | `orca environment list` が空。bot は手元の Mac のローカルだけ | スリープ中は bot が止まる。GitHub からの依頼は最大 1 日待たされる |
| `gh` の project 権限 | token scope に `project` が無い | Project の作成と Status 更新ができない。`gh auth refresh -s project` が必要（ブラウザ認証＝手作業） |
| GitHub Actions | `.github/workflows/check.yml`（`bridge` / `android`）。2026-11-23 に PR #6 で両方緑を確認してマージ | `bridge` を必須 check にしてブランチ保護を入れた。`android` は 60 分枠で重いので、緑が続いたら必須に足す |
| CD | デプロイの仕組みが無い（Android アプリ＋ローカルのブリッジ） | Release Captain の Deploy watch Webhook は段階 5 で後回し |
| ブランチ保護 | 非公開リポジトリでは有料プランが必要 | 失敗したら画面で確認する |

## 画面で 10 体を作って分かったこと（2026-11-23、Orca 実機）

| 項目 | 実機の挙動 | テンプレートでの扱い |
| --- | --- | --- |
| 作成フォームの Identity 欄 | **200 字まで**。指示文の全文（1,600〜4,400 字）は入らない | Identity には役割の 1 段落だけ入れて作成し、直後に `scripts/install-souls.sh` で `SOUL.md` を全文にする。末尾の `## Never` はチームの禁止事項（`bots/_never.md`）に置き換える（下の「稼働 1 日目で分かったこと」） |
| 新しい bot の権限 | 既定は「Same as chats · Full access」 | 作成フォームのエージェント選択で **Ask for approval** に変える（作成後はチャット欄の Permissions で確認できる） |
| Look around | **作成時点で全 bot が On**（平日 8〜20 時、4 時間ごと） | bot の Home → Automations → Look around で PMO 以外を Off |
| Who can ask | 既定は自分だけ（GitHub コネクタ追加時の画面で確認できる） | そのまま |
| 自動化（スケジュール・イベント） | `orca automations create --bot <名前>` で作れる。依頼文をチャットに貼って bot に作らせる必要は無い | `scripts/setup-automations.sh` にした |
| イベント起動 | その bot に **GitHub コネクタが無いと作成を拒否される**（`has no GitHub connector`）。コネクタは bot ごと | 各 bot の Connectors → Add a connector → GitHub → Turn on。オーナーの GitHub の接続は bot の間で共有なのでサインインは不要 |
| **自分の操作では起動しない** | 「Your own pushes, comments, reviews and labels start nothing (the bot works as you)」。1 人開発では、自分で付けたラベル・自分で立てた issue・自分への review request ではイベントが発火しない。発火するのは CI の結果・マージ・クローズ・デプロイ・セキュリティアラートと、`pr_opened` に `from=me` を付けたものだけ | ラベル起動（Fixer / Conductor / Ops Scribe）と issue 起動（Intake）は協働者向けに残すが、**自分が頼むときは issue のコメントで `@orca-bots <bot>` とメンションする**（メンションは自動化なしで直接届く）。Reviewer は `github.pr_opened from=me` |
| Orchestration | 実験的機能の切り替えは無くなり、Settings → Orchestration に常設。入れ子の深さの既定は 4 | 深さを 2 に下げた |
| ルーム | New bot or group → New group。メンバーは 2 体以上。チェックボックスで選ぶ | 開発ルーム（6 体）・出荷ルーム（3 体） |
| Ask for approval の粒度 | 読むだけの `gh issue view` にも 1 回ずつ「Allow Bash?」が出る（Conductor の試運転で確認） | 読むだけのコマンドを `bots/_settings.json` で事前許可し、`install-bot-settings.sh` で各 bot の `.claude/settings.json` に配る。効き目は試運転で確認中 |
| 変数展開を含むコマンド | `"${ORCA_CLI_COMMAND:-orca}" ...`（Orca のスキルが教える書き方）は「A variable in braces ... can't be checked」で、事前許可があっても毎回確認になる | 共通ルールで `orca` と直接書かせ、パイプも付けさせない。`_settings.json` から変数展開の形を外した |
| 確認を減らす（2026-11-23 オーナー判断） | 読み取り・Run の中の操作・`worker-start`・作業ブランチへの push を事前許可。`main` への push・強制 push・ブランチの削除・`gh pr merge` を拒否。拒否は `*` を使ったパターンを含む（Claude Code の `*` の扱いは未検証） | `bots/_settings.json.tmpl` |
| 権限モード（2026-11-23 オーナー判断） | Ask for approval では、bot がコマンドをパイプや `;` でつなぐたびに止まる（指示しても癖が残る）。全 bot を **Approve for me**（Orca が確認を審査）にした。Bot settings の Permissions は「新しい会話の初期値」で、進行中の会話には効かない | SETUP.md 3-2 |
| bot の作業場所 | bot の current は**リポジトリではなく bot のホーム** | Conductor のワーカーは `--worktree new-top-level --repo path:<リポジトリ>` で立てる |
| TDD の段と ADR（2026-11-23 オーナー判断） | Orchestration のタスクの依存（`--deps`）は「前のタスクが終わったら ready」になるだけで、RED・GREEN の中身は確かめない | Conductor が段ごとにワーカーを分け、RED の確認（コミットの中身・失敗の理由）・GREEN の確認（テストのファイルの差分が空）・REFACTOR の確認（`refactor(…)` か変えなかった理由、テストの差分が空、check が通る）をしてから次の段を起動する。テスト（claude）・実装（codex）・リファクタリング（claude）の担い手を分ける。アーキテクチャの方針は ADR（`ADR_DIR`、雛形は `shared/adr-template.md`）に残し、仕様の段で案を出して設計の承認で一緒に承認をもらう |
| ワーカーの作業場所の後片付け | `worker-release`（worker_done の約 2 分後に自動）は端末を閉じるだけで、**作業場所（`~/orca/workspaces/<repo>/<名前>`）とローカルの作業ブランチは残る**。消すのは `orca worktree rm --worktree path:<作業場所> --delete-branch`（未コミットの変更があると消えない。`--delete-branch` はマージ済みと分かるブランチだけ消す） | 2026-11-23 オーナー判断: 作業が完了したら最後に消す。Conductor が `pr_merged` で起きて自分の Run の作業場所を消す。リモートのブランチは消さない |
| bot のフォルダ名 | 作成時の名前のスラッグ（`CI Guardian` → `ci-guardian`）。改名に追従しない | 名前で引く（SETUP.md 節 0） |

## ブランチ保護の設計判断

設計書は「人のレビュー承認と必須 check をマージ条件にする」としている。
だが bot の PR はすべてオーナー名義で作られ、GitHub は **PR 作成者の自己承認を認めない**。
1 人開発で必須承認を 1 件にすると、どの PR もマージできなくなる。

そこで保証の本体を「`main` への直接 push を塞ぐ」ことに置き、
`REQUIRED_APPROVALS=0` を既定にした（`team.config` で変えられる）。
人のレビューは Reviewer bot の指摘を読んだ人が**マージボタンを押す**ことで担保する。
協働者が増えたら `REQUIRED_APPROVALS=1` に上げる。

remote-code-watch では 2026-11-23 にこの運用を採用した。
「原則、作業ブランチを切って push し、`main` へのマージは PR で行う」。
手元で `--no-ff` マージして `main` を push する運用は廃止し、`REQUIRED_CHECKS='bridge'` で保護を入れた。

**注意（2026-11-23 のレビューで指摘）**: 保護は `enforce_admins: false` なので管理者には効かない。
bot はすべてオーナー＝管理者の名義で動くため、bot の `git push origin main` や `gh pr merge` は保護では止まらない。
保護が防ぐのは人の誤操作だけで、bot への歯止めは指示（`_common.md`）と Ask for approval。
bot も保護で止めるには `enforce_admins` を On にする（人も PR 経由が強制される）。
remote-code-watch では 2026-11-23 に **Off のままにすると決めた**（緊急時に人が直接直せる抜け道を残す）。

**再確認（2026-11-23、rcw PR #11 の Sentinel の検査のあと）**: その後、権限を Approve for me にし、ワーカーの起動と
作業ブランチへの push を事前許可にしたので、**ワーカーが無人で動く経路**ができた。ワーカーは確認なしで動き、
bot の拒否リストもワーカーには効かず、拒否リスト自体もコマンドの形の照合なので抜けがある
（引数なしの push、完全名の ref、`gh api` 経由のマージ）。Sentinel は `enforce_admins` か bypass なしの ruleset を推奨したが、
オーナーは**それでも Off のまま**と判断した。受け入れたリスク: ワーカーが指示を外れるか、読んだ PR 本文などの指示に乗せられて
`main` へ push した場合、GitHub 側では止まらない。歯止めはタスク仕様・共通ルールの指示・拒否リスト（補助）と、
Sentinel が `pr_merged` のたびに差分を見ること。同じ検査で出た「Reviewer が本文の文字で Conductor の PR と判断する」点は、
Conductor が head のブランチを自分のエピックのブランチと照らしてから動くように直した。

**bot の関門を必須の check にした（2026-11-24 オーナー判断）**: `REQUIRED_CHECKS='bridge,orca/review,orca/security-review'`。
`orca/` の 2 つは Reviewer と Sentinel が `gh api …/statuses/<SHA>` で付ける commit status で、GitHub App ではないので必須の check は `app_id: -1`（どこから付いてもよい）で入れた
（`setup-github.sh` が `orca/` で始まるものをそうする）。`strict`（最新にしてからマージ）は残したので、Update branch のあとは 2 つが付き直すまでマージできない。
きっかけは、#34 が main の取り込みのコミットでレビューもセキュリティレビューも無いままマージされたこと。
`enforce_admins` は Off のままなので、管理者（オーナーと、オーナー名義の bot）は保護を押し切れる。bot は `gh pr merge` を判定フックが断る。

## 稼働 1 日目で分かったこと（2026-11-23、rcw）

自動化の実行は 14 件（Reviewer の PR オープン 4、Sentinel のマージ時 6 と月曜の定時 1、Conductor のマージ時 3）。
Intake・Fixer・CI Guardian・Doc Keeper・Ops Scribe・Release Captain・PMO は 0 件だった。

| 項目 | 分かったこと | 対応 |
| --- | --- | --- |
| オーナーの操作とイベント | `orca automations trigger-options` によると、オーナーの push・コメント・レビュー・ラベルでは起動しない。例外は CI の結果、PR のマージ・クローズ・競合、デプロイ、セキュリティアラート、ワークフローの完了、`from=me` を付けた PR オープン。`from=me` は `pr_opened` だけ。bot もオーナー名義なので、bot が立てた issue（#14 #15）は Intake に届かず手つかずだった。1 人開発なので Intake の `issue_opened` は一度も起きない | bot 同士は Orca のメール（`orca orchestration send --to bot:<名前>`）で渡す（`_common.md`「連絡の経路」）。人の issue は Intake の毎時の見回りが拾う |
| Orca の既定の Never | 作成時に全 bot の `SOUL.md` の末尾へ「Change anything (comments, labels, pull requests, posts anywhere but here) until my owner says I can. I start by reading and reporting only.」が入る。Sentinel の「変更したものはありません」「決めてもらえれば進めます」はこれに従った結果 | `scripts/install-souls.sh` が Never をチームの禁止事項（`bots/_never.md`）に置き換える |
| 指摘が会話で止まる | Reviewer #12（軽微 3 件）、Sentinel #12・#13・#17 の指摘が「人が決めて」「渡せます」で終わった。Sentinel #9 の指摘は自分のメモリで「来週追う」 | 指摘は「その PR で直す」か「issue にする」のどちらか（`_common.md`「取りこぼさない」）。issue には重複防止の鍵 |
| bot への答えが届かない | Sentinel が Reviewer の質問に `orchestration reply --id msg_item_…` で答え、`terminal_not_found` で失敗。Reviewer の「回答が来たら伝えます」は果たされなかった | bot への答えは `send --to bot:<相手> --type status`。`reply` は自分の Run のワーカーにだけ |
| `bot reply` の失敗 | メールで起きたチャットはスレッドに結びつかず、`orca bot reply` が「Nothing was posted」で失敗する | `gh pr comment` / `gh issue comment` で書く |
| 「Working…」のまま | Reviewer が PR #16・#17 に「Working…」を出したが、実行の記録（`orca automations runs`）もセッションも無い。原因は不明（Orca 側） | Reviewer は結果に `<!-- orca-review: <SHA> -->` を残し、見回り（`scripts/sweep.sh`）が印の無い PR を Reviewer に頼み直す |
| 確認で止まった回数 | 試運転の最初の 3 回だけ（Conductor が `"${ORCA_CLI_COMMAND:-orca}"` で包んだ呼び出し）。Approve for me にしてからは 0。ただし bot は `cd … &&` や `O=orca; $O` を使い続けている（Orca の審査で通っている） | issue・PR の作成とコメント、Project の更新を事前許可に足した。`gh api` の書き込み（merge の抜け道）、PR の承認、リリース、`-C` 付きの `main` への push を拒否に足した |
| ラベルの起動はオーナー名義でも発火した | Intake が `gh issue edit` で `bot:fixer` を付けたら、Fixer のラベルの自動化が #14・#15 で 1 回ずつ起動し、Intake のメールと合わせて Fixer の会話が 3 つ立った（後から来た 2 つは「別の会話が担当中」と判断して手を引いた）。`automations runs` には記録が残らない。trigger-options の「自分のラベルでは起動しない」とは違う | ラベルの起動（Fixer・Conductor・Ops Scribe）を止め、受け渡しを Intake のメールに一本化した（`setup-automations.sh` の `off`） |
| Home Chat の権限モード | bot 宛てのメールは `--chat` が無いと Home Chat に届く。Home Chat はセットアップの時（Ask for approval）から続く会話で、権限モードの変更が効かない。Reviewer の `status` を受けた Intake の Home Chat が、自分の `MEMORY.md` の編集で人の確認を出して止まった | bot 宛てのメールはすべて `--chat new`。自分のメモリ（`MEMORY.md`・`memory/`）の編集を事前許可した（`{{BOT_DIR}}`。`install-bot-settings.sh` が bot ごとに入れる） |
| bot の権限モードの正体 | Approve for me は Claude Code の auto モード（`--permission-mode=auto --permission-prompt-tool=stdio`）。分類器が危ないと見た操作は人に回る（Fixer の `"${ORCA_CLI_COMMAND:-orca}" automations remove …` で確認が出た）。セットアップ時からの会話は `default`（確認を出す）のまま。ワーカーは `--dangerously-skip-permissions` | PreToolUse フック `scripts/bot-guard.py` を全 bot の `.claude/settings.json` に入れた。禁じた操作は deny（理由を返す）、それ以外は allow。フックは権限モードに関係なく先に効く |
| bot のフォルダの信頼 | `~/.claude.json` で信頼済み（hasTrustDialogAccepted）なのは Intake のフォルダだけ。未信頼のフォルダでは `.claude/settings.json` の `permissions.allow` が無視される（headless の claude が警告を出す）。つまり 8 体では配った許可リストが効いていなかった。フックは未信頼のフォルダでも動く（2026-11-23 に headless の claude で確認） | 判定はフックに寄せた。許可リストは信頼済みのときの補助 |
| `*` と `:*` の混在 | `Bash(git push * :*)` は「`*` と末尾の `:*` が混ざると文字どおりに照合する」と警告が出て効かない | 3 つ外した（コロンで始まる refspec の削除はフックが断る） |
| セキュリティレビューの時期（2026-11-23 オーナー判断） | Sentinel の検査は PR のマージ時（マージの後）に動いていた。rcw の CLAUDE.md は「main にマージする前に `security-review` を通す」 | マージの前に移した。Reviewer が通す → Sentinel がワーカーで `security-review` を通し、5 つの観点でも見る → `orca/security-review` を付けて人にマージを頼む。マージ時の起動は、レビューを経ずにマージされたときの後追いだけ。commit status は `gh api repos/<repo>/statuses/<SHA>` で、bot-guard は context が `orca/` のものだけ通す |
| 引用したメンションで起きる | Intake が #8 の本文「@orca-bots reviewer Hello」をコメントに引用し、Reviewer が起きた | 共通の決まりで、`@orca-bots` を引用しない・案内はコードで囲む |
| 新しい要件の行き先（2026-11-24 オーナー判断） | 人が立てた要件は #10 だけで、Conductor が 1 issue = 1 エピックとして詳細化・承認・Run までこなした。複数エピックの要件を分ける段と、実装計画（§4 の一覧・トレーサビリティ）を受け持つ担当が無かった（E-46 の設計ワーカーは「承認範囲の外」として足さなかった）。Conductor は Run を 1 つずつ回すので、#21 は #19 の Run の後まで設計の案が出なかった | 11 体目の Planner を足した。要件 → 計画 PR（要件書と仕様書の ID）→ マージ＝承認 → 子 issue（sub-issue・blocked by）→ Intake。計画 PR で承認したエピックは、ADR の案・要件書からの逸脱・凍結済みテストへの影響があるときだけ Conductor が承認を求める。実装計画の行は Conductor の設計ワーカーが自分のエピックの分を足す |
| sub-issue と blocked by | rcw で `issues/<n>/sub_issues` と `issues/<n>/dependencies/blocked_by` が読める（2026-11-24）。issue の一覧（REST）にも `sub_issues_summary` と `issue_dependencies_summary` が入る。`gh issue list --json` には無い | Planner が書く（bot-guard はこの 2 つの POST を、ほかのフィールドを付けないときだけ通す）。見回りは REST で取り、依存が開いている issue を催促しない |
| main の取り込みでレビューが外れる（2026-11-24） | main の保護は「最新にしてからマージ」（strict）。#29・#32・#34 はレビューのあとに「Merge branch 'main' into …」のコミットができ、そのコミットでマージされた。#34 はその SHA にレビューもセキュリティレビューも無く、#29・#32 は Reviewer の印が無かった（Sentinel だけ通し直していた）。取り込みは作者の bot が知らないので誰も再レビューを頼まず、見回りは 60 分待つ | Reviewer と Sentinel は、新しい head が「前に通した SHA ＋ main」のマージで `git show --remerge-diff` が空なら前の結果を引き継ぐ。見回りは取り込みのコミットを待たずに拾う。Sentinel のマージの依頼に SHA と「取り込んだら通し直す」を添える。必須の check にするかはオーナー判断 |
| Sentinel を開発の流れに組み込む（2026-11-24 オーナー指示） | Sentinel は出荷ルームだけにいて、関わるのはマージ前の 1 か所だった | 要件（Planner が計画 PR の前に脅威分析を頼む。要件書に「セキュリティ要件」と `AC-S`）、設計（セキュリティに触れるエピックは Conductor が Run の前に設計のセキュリティレビューを頼み、攻撃ケースを RED に入れる）、マージ前（すべての PR）の 3 か所にした。開発ルームにも入れた。完了報告で Planner が子の PR ごとのセキュリティレビューを確かめる |
| ルームの説明文が古い | 開発ルームの Group settings → Members の説明文は、Sentinel が「マージされた変更を検査し…」、Fixer が「修正を始めてよいかを人に確認してから」など作成時の文のまま。SOUL.md は新しい（bot が読むのは SOUL.md）。新しく作った Planner だけ今の SOUL.md の冒頭が出る | 表示だけの古い控え。動きには関係しない。Identity を画面で直すと SOUL.md を書き換えるおそれがあるので触らない |
| bot の作成画面（2026-11-24） | New bot or group のメニューは、背景の Computer Use では開けない（`background_unavailable`）。オーナーの許可を得て前面化（`--restore-window`）した。作成フォームの Agent → Permissions で Approve for me を選べるようになっていた | 作成は前面化が要る（人に聞いてから）。権限は作成フォームで Approve for me にできる |
| 定時が当日に走らない | CI Guardian（月曜 9:30）と Release Captain（平日 8:30）は 9:40 に作ったので、初回は次の回（`nextRunAt`） | 問題なし |

## 受け渡しをルームと GitHub に移す（2026-11-25、rcw、オーナー指示）

メールは受け手に新しい会話を 1 本ずつ増やし（Conductor 40、Sentinel 40、Intake 27）、人から流れが見えなかった。
「bot 同士の受け渡しは GitHub のイベントとルームでのメンションで行い、メールを起点にしない」に変えた。試験と記録で次を確かめた。

| 項目 | 分かったこと | 対応 |
| --- | --- | --- |
| ルームの `@` で相手が起きる | 自動化（`--once --by`、`--runs-in chat:<Intake のルームの会話>`）で Intake をルームで動かし、返事に `@Fixer …` と書かせた。Orca が Fixer に渡し（記録の `handedOff`、ルームに「Intake asked Fixer」）、Fixer が約 2 秒後にルームで答えた | 受け渡しは開発ルームの返事の `@名前`（`_common.md`「連絡の経路」） |
| 自動化をルームで動かせる | `--runs-in chat:bot-group-member-…`（`orca bot chats --bot <名前>` で題名がルーム名の会話）で、依頼文がオーナーの書き込みとしてルームに出て、bot の返事もルームに出る | `setup-automations.sh` が全部の自動化をルームの会話で作り直す（`--results-to chat`） |
| ワーカーの完了もルームに返る | Planner をルームで動かしてワーカーを 1 つ立てさせた。worker_done でルームの会話が起き直し、続きの返事がルームに出た（「Planner followed up」） | Fixer・Conductor・Planner の Run もルームの会話で回せる |
| ルームの会話は bot のフォルダで動く | セッションの記録の場所が `~/.orca/bots/<名前>`（ルームの `group-bot` ではない）。SOUL.md とフックが効く | — |
| ルームの会話の権限モード | 11-23 に作ったルームの会話は `ask`（Reviewer は `full-access`）、11-24 に足した Sentinel・Planner は `auto` だった。入力欄の Permissions は **Replies で選んだ bot の会話**に効く（選び直すと記録が `auto` に変わる。動いているプロセスには次のターンから） | 13 本すべて Approve for me にした（前面化はオーナーの許可を得た）。SETUP 3-6 に手順 |
| ルームに書く CLI は無い | `orca bot reply` は起きたスレッドにしか書けない。ルームの会話へのメールは「同じルームのメンバーからしか受け付けない」と断られる | ルームの外で起きた bot（人の GitHub メンションなど）は、issue / PR に `@orca-bots <役割>` のコメントで渡す |
| bot 名義の GitHub メンション | Sentinel の PR #34 へのコメントと、Intake の needs-info のコメントに入っていた `@orca-bots reviewer` で Reviewer が起きていた（Reviewer のチャットの題名と最初の依頼文） | ルームの外からの受け渡しに使う。Orca の説明には無い挙動なので、変わったら見回りが拾う |
| GitHub のイベントの範囲 | bot（オーナー名義）の操作で起きるのはマージ・close・conflict・CI の結果だけ。bot の作業場所から開いた PR は `from=me` でも起きない（bots リファレンス） | issue を立てた・PR を開いた・ラベルを付けたは、必ず `@` で渡す |
| ルームのメンバー | `@` で渡せるのは同じルームの bot だけ。Release Captain・Ops Scribe は出荷ルームにしかいなかった | 開発ルームに 10 体全員を入れた（オーナー判断）。出荷ルームは人との相談に残す |
| メールを断る | `orca orchestration send --to bot:…` は bot-guard が断り、ルームの `@` と GitHub のメンションを案内する。`--to dispatch:` と worker_done は通す | 試験 64 件 |
| GitHub のイベントもルームで動く | rcw#54 で `orca/review` が failure になると、CI Guardian の「check 失敗」（`ci_failed`）が開発ルームの中で起きた | `orca/` で始まる check の失敗は bot のレビューの結論なので、CI Guardian は何もしない（`ci-guardian.md` の 0） |
| `pr_opened from=me` の当たり外れ | 説明（bot の作業場所から開いた PR では起きない）と逆に、bot が開いた PR（#42・#48・#53）で Reviewer が起きた。オーナーがこの端末の Claude Code から開いた PR は、#17・#18・#39・#54 で起きず、#56 では起きた（2026-11-25 に訂正。最初は「一度も起きない」と書いていた）。起きない理由は分かっていない | 起きる前提にしない。起きなかった PR は見回り（印の無い PR、60 分後）が Intake から Reviewer に `@` で渡す。急いでルームで頼むと、イベントと二重になることがある（rcw#56 は 2 回レビューされた）。頼む前に数分待ち、ルームに Reviewer の返事が無いことを確かめる |
| コードで囲んだ `@orca-bots` にも反応する | rcw#54 の Reviewer のコメントに、インラインコードの `` `@orca-bots <役割>` `` があり、6 秒後に Orca の GitHub アプリが「Choose your default bot to start」と返した | GitHub に書く文には `@orca-bots` の文字を入れない（渡すときを除く）。人への案内は開発ルームの `@名前` か Needs you にした（`_common.md`・Conductor・Planner・Sentinel） |
| ルームでの承認の書き込み主（rcw #55、Sentinel の指摘） | 開発ルームには bot も書き込み、自動化の依頼文もオーナーの書き込みとして出る。紛れた指示に従った bot が `@Conductor 承認` と書くと、人を待つ場面を人なしで通れる筋道があった | 人の答えとして扱うのは、開発ルームで人が自分で書いた書き込みと Needs you の答えだけ。bot の書き込み・`[Orca event` の印より後ろの引用・GitHub のコメントは承認にしない。bot は `@<相手> 承認` を書かない（`_common.md`・Conductor・Planner） |
| マージのイベントもルームで動く | rcw#54 のマージで、Conductor・Sentinel・Planner の `pr_merged` の自動化が開発ルームの中で起きた。Conductor は #55 の決まりどおり「開発ルームにオーナーの承認の書き込みが無い」として E-49 を待たせた | — |
| `contains=` は本文にも効く | Planner の「計画 PR のマージ」（`contains="Planner"`）が、題名に Planner の無い rcw#54 で起きた（本文に Planner の語がある） | Planner は題名と `作業 ID: req-` で自分の計画 PR かを確かめて 1 行で終えた。動きは決まりどおり |
| マージのあとの push（3 回目） | rcw#54 は 0691f3a でマージされ、そのあと push した ec78bb8 は main に入らなかった（#16・rcw#18 と同じ） | rcw#56 に移した。PR に足す前にマージ状態を確かめる |

## 次に確認すること（試運転で見る）

1. bot のセッションから `orca orchestration` が実行できるか。
   Ask for approval での確認回数が現実的か。動かなければ、人が Orca のターミナルで Run を回し、
   Conductor は仕様化と報告だけに落とす。
2. 開発ルームの `@` の受け渡しが、実際の issue・PR で最後まで回るか（Intake → 担当 → Reviewer → Sentinel → 人のマージ）。同じ bot に続けて `@` が来たとき、ルームの会話で順番に処理されるか。ルームの会話が長くなったときに、前の仕事の話を持ち込まないか。
3. bot が `gh project` で Status を Ready → In review まで動かせるか。
4. `orca skills get orchestration --full` の内容が、`bots/conductor.md` のコマンドとずれていないか
   （Orchestration は実験的機能で、旧コマンドが廃止された前例がある）。
5. Intake の見回りの precheck（`scripts/sweep.sh`）が、拾うものが無い時間に `skipped_precheck` になるか（`orca automations runs --id <見回りの id>`）。
   定時の RRULE は `BYHOUR` に 1 つの時刻しか受け付けない（「FREQ=DAILY with BYHOUR and BYMINUTE」）。毎時 7〜23 時は cron `15 7-23 * * *` で書いた。
6. 権限の `*` を使ったパターン（`git -C * push * main`、`gh api * -X *` など）が、Claude Code で意図どおりに当たるか。
7. （2026-11-25 に本文にも効くと確認）Planner の自動化の `contains=` が、`github.pr_merged` / `github.pr_closed` で PR の題名か本文に効くか。効かなければ、計画 PR のマージで Planner が起きず、見回りが最大 1 時間遅れで拾う。
8. sub-issue と blocked by の書き込み（`gh api … -F sub_issue_id=` / `-F issue_id=`）が、bot の権限で通るか。`issue_dependencies_summary.blocked_by` が「開いている依存の数」か（閉じたら 0 に戻るか）。
9. bot の返事の中の `@名前` の誤爆（説明や引用で書いて相手が起きる）と、`@` の往復が止まらない例が出ないか。出たら決まり（`_common.md`）を足す。
10. 名前に空白がある bot（`@Doc Keeper`・`@CI Guardian`・`@Release Captain`・`@Ops Scribe`）への、ルームの返事の `@` で相手が起きるか。
