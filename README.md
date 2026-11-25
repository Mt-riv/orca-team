# orca-team — Orca Bots 11体チームのテンプレート

複雑なアプリ開発と継続的デリバリーを [Orca](https://github.com/stablyai/orca) の Bots で回すための雛形。
1 リポジトリ = 1 チーム（11体）を前提に、同じ構成を他プロジェクトへ展開して増やせるようにしてある。

Orca の公式のものではない。1 人開発のリポジトリで実際に回しながら直してきたもので、
Orca の実機の挙動（説明と違ったところを含む）は [VERIFY.md](VERIFY.md) に記録してある。

## 前提

- macOS（シェルは bash 3.2 で動くように書いてある）
- Orca（v1.4.269〜v1.4.273 で確認。Bots と Orchestration を使う）
- `gh`（`project` スコープ付きでログイン済み）、`python3`、`git`
- bot が扱う GitHub リポジトリ 1 つと、そのホスト上のクローン

## これは何を自動化しないか

Orca の公開 CLI には **bot の作成・権限設定・コネクタ接続のコマンドが無い**（`orca --help` の Bots 節は
`bot reply` と `bot connectors` だけ）。つまり bot 本体は必ず人が Orca の画面で作る。
このテンプレートが用意するのは次の3つで、それ以外は `SETUP.md` の手作業チェックリストに回してある。

| 種類 | 中身 |
| --- | --- |
| 指示文 | `bots/*.md`。bot を作った後に `~/.orca/bots/<id>/SOUL.md` へ書き込む本文と、オートメーション依頼文 |
| GitHub 側の設定 | Issue フォーム、ラベル、ブランチ保護、Project（`scripts/setup-github.sh`） |
| 展開手順 | `SETUP.md.tmpl` → 展開先の `bots/SETUP.md`（段階1〜5の作業順と「次へ進む条件」） |

## 使い方（新しいプロジェクトへ横展開するとき）

設定ファイルは自分の環境（パス・リポジトリ名）なので、このリポジトリの外に置く（例 `~/orca-teams/`）。
下の例では、このリポジトリを `~/dev/orca-team` にクローンしたものとする。

```bash
cd ~/dev/orca-team

# 1. 設定ファイルを作る（対象リポジトリの外、このリポジトリの外に置く）
mkdir -p ~/orca-teams
cp team.config.example ~/orca-teams/team.<project>.config
$EDITOR ~/orca-teams/team.<project>.config

# 2. 対象リポジトリへレンダリングする（bots/ と .github/ が作られる）
scripts/render.sh ~/orca-teams/team.<project>.config

# 3. GitHub 側を設定する（ラベル・Project・ブランチ保護）
#    ブランチ保護を後回しにするなら --skip-protection を付ける
scripts/setup-github.sh ~/orca-teams/team.<project>.config

# 4. bot 本体・権限・GitHub コネクタ・ルーム・Look around は画面で作る（bots/SETUP.md の段階 3〜6）
#    Orca Computer Use で自動化できる（アクセシビリティ許可とウィンドウの前面化が要る）

# 5. 自動化（定時とイベント起動）を作る。コネクタを付けたあとに流す。何度流してもよい
scripts/setup-automations.sh ~/orca-teams/team.<project>.config

# 6. 事前許可（読み取り・issue と PR の作成・Run の操作）と拒否リストを各 bot に配る
scripts/install-bot-settings.sh ~/orca-teams/team.<project>.config

# 6.5 指示文を各 bot の SOUL.md に入れる（末尾の Never もチームの禁止事項に置き換える）
scripts/install-souls.sh ~/orca-teams/team.<project>.config

# 7. 全チーム共通の PMO に、すべてのチームを渡す
scripts/render-pmo.sh --install ~/orca-teams/team.*.config
```

レンダリングした `bots/SETUP.md` には、このリポジトリと設定ファイルの絶対パスが入る
（`{{TEMPLATE_DIR}}`・`{{CONFIG_PATH}}`）。bot の判定フックと見回りも、このリポジトリの `scripts/` を直接呼ぶ。
このリポジトリを動かしたら、`render.sh`・`install-bot-settings.sh`・`setup-automations.sh` を流し直す。

## 止まらずに回すための決まり（2026-11-23 の稼働実績から）

- **bot 同士は開発ルームの `@名前` で渡す（2026-11-25 から）。** 自動化（定時・見回り・GitHub のイベント）はすべて開発ルームの中で動き、
  bot は返事の最後に `@<相手> <issue / PR> <してほしいこと>` と書いて次の bot を起こす。人は開発ルームを見れば流れを追える。
  Orca はオーナーの操作では自動化を起動せず、bot もオーナー名義で動くので、bot が立てた issue・付けたラベル・開いた PR では次の bot は起きない。
  GitHub のイベントで動くのは、マージ・close・conflict・CI の結果だけ。Orca のメール（`orca orchestration send --to bot:`）は判定フックが断る。
  ルームの外で起きた bot（人の GitHub メンションなど）は、issue / PR に `@orca-bots <役割>` のコメントで渡す。
- **指摘は「その PR で直す」か「issue にする」。** 人に「決めて」で終えない。issue は Intake に渡し、Intake が担当を決めて渡す。
- **見回り。** Intake が毎時（7〜23 時）、`scripts/sweep.sh` で未振り分けの issue・レビューの印が無い PR・止まった担当を拾う。
  拾うものが無い時間は precheck で起動しない。
- **人を待つのは 4 つの場面だけ**（設計の承認、PR のマージ、凍結済みテストの変更、依頼の範囲外の判断）。待っている issue・PR には `wait:human`。
- **issue 1 件 = PR 1 本 = 担当 1 体。** 順番は GitHub の依存（blocked by）で持ち、依存が開いている issue には着手しない。見回りも催促しない。

## 新しい要件の流れ（2026-11-24 から）

人の要件は Planner が受け持ち、詳細化・実装計画・分割を **計画 PR 1 本** にまとめる。計画 PR のマージが「要件と計画の承認」になる。

```text
人: issue（フォーム「要件・要望」、ラベル requirement）か、Planner とのチャット
  → Intake: bot:planner を付けて Planner へ
  → Planner: 調査ワーカー（req-<n>-research）→ 大きさを決める → Sentinel に脅威分析を頼む（セキュリティ要件と AC-S）
       早道（1 エピックで収まり、仕様書の ID も変わらない）→ 要件を整えて担当へ直接渡す
       計画 → 計画ワーカー（req-<n>-plan）が要件書 `<REQ_DIR>/R-<n>.md` と仕様書の ID を PR にする
  → Reviewer → Sentinel（脅威分析が要件書に入ったかも見る）→ 人がマージ ＝ 要件と計画の承認（論点は推奨どおり）
  → Planner: 分割の表どおりに子 issue を立てる（sub-issue、blocked by）→ Intake が担当に振る
  → 各担当: 依存が閉じたものから着手。セキュリティに触れるエピックは Run の前に Sentinel の設計レビュー（攻撃ケースを RED に）
  → PR → Reviewer → Sentinel（マージ前のセキュリティレビュー）→ 人のマージ
  → Planner: 子がすべて閉じたら、要件の受け入れ条件と、子の PR ごとのセキュリティレビューを突き合わせて完了報告を書き、要件を閉じる
```

- 計画 PR で承認したエピックは、Conductor が次の 3 つのどれかに当たるときだけ設計の承認を求める（2026-11-24 オーナー判断）。
  ADR の案、要件書からの逸脱、凍結済みテストへの影響。
- **Sentinel（セキュリティ担当）は 3 か所で入る**（2026-11-24 オーナー指示）。要件（計画 PR の前の脅威分析）、設計（セキュリティに触れるエピックの Run の前）、マージ前（すべての PR）。
  main を取り込んだだけのコミット（Update branch）は、衝突の手直しが無ければ Reviewer と Sentinel が前の結果を引き継ぐ（見回りは待たずに拾う）。
- E 番号は Conductor が着手するときに振る。子 issue は仮 ID `R-<要件の番号>-<a, b…>`。
- 計画 PR のマージは GitHub のイベントで Planner を起こす。取りこぼしは見回りが拾う（計画 PR がマージ済みで子が無い要件、子がすべて閉じた要件）。
- 要件書の雛形は `shared/requirement-template.md`（`render.sh` が `<REQ_DIR>/0000-template.md` として置く。`REQ_DIR` の既定は `docs/requirements`）。

詳しい根拠は `VERIFY.md` の「稼働 1 日目で分かったこと」。

`render.sh` は `{{KEY}}` を設定ファイルの値で置き換えるだけなので、
テンプレート側を直せば全プロジェクトに同じ修正を配れる。
逆に、プロジェクト固有の言い回しはレンダリング後のファイルではなく設定ファイル側に寄せる。

## チームを増やすときの命名規則

同じ Mac の Orca では、bot は**名前**で区別される（`bot:<名前>`、`automations create --bot <名前>`、
ルームでの `@名前`、GitHub での `@orca-bots <名前>`）。フォルダ名（スラッグ）は作成時の名前から付き、改名に追従しない。
名前が重なると呼び分けられないので、2 つ目以降のチームは次の規則で名前を付ける。

| 対象 | 最初のチーム（`TEAM_CODE=''`） | 2 つ目以降（例 `TEAM_CODE='ml'`） |
| --- | --- | --- |
| bot | `Reviewer`、`CI Guardian` … | `ml-reviewer`、`ml-ci-guardian` …（名前＝フォルダ名＝メンション名） |
| GitHub で呼ぶ | `@orca-bots reviewer` | `@orca-bots ml-reviewer` |
| ルーム | `開発ルーム`、`出荷ルーム` | `ml 開発`、`ml 出荷` |
| 自動化 | `Reviewer: PR が開かれたとき` | `ml-reviewer: PR が開かれたとき` |
| PMO | `PMO`（全チームで 1 体） | 作らない。`render-pmo.sh --install` で表に足す |

- 略号は英小文字と数字だけ（`render.sh` が検査する）。短く、リポジトリから想像できるものにする
- 2 つ目以降は、名前を最初から小文字のスラッグにしておくことで、フォルダ名とメンション名が名前と一致し、ずれが起きない
- 名前の組み立ては `scripts/names.sh` の 1 か所だけ。`render.sh`・`setup-automations.sh`・`install-bot-settings.sh` がこれを使う
- 最初のチームは略号なしの名前のまま使い続ける（後から略号つきに改名しない。フォルダ名が改名に追従しないため）

## チーム構成（11体）

| bot | ライン | 担当 | 起動トリガー | ベースのテンプレート |
| --- | --- | --- | --- | --- |
| Planner | 計画 | 人の要件を詳細化し、実装計画と分割を計画 PR にまとめ、マージ後に子 issue を立てる。子がすべて閉じたら完了報告 | Intake の `@`、計画 PR のマージ・close、チャット | Spec drafting＋独自指示 |
| Conductor | 指揮 | エピック 1 件を仕様化し、Run でタスク分解・ワーカー起動・統合PRまで TDD で進める | Intake の `@`、PR マージ（片付けと次の issue）、チャット | Spec drafting＋独自指示 |
| Intake | 入口 | 新規 issue の整理、重複検出、種類・優先度・担当を決めて渡す。毎時の見回り | bot の `@`、毎時の見回り、新規 issue | GitHub issue triage |
| Fixer | 入口 | 不具合の再現と原因特定、TDD の修正PR。Planner の小さな変更も作る | Intake の `@`、issue でのメンション | Bug investigation |
| Reviewer | 品質 | PR の危険な変更とテスト不足をファイル・行つきで列挙 | 人が開いた PR、bot の `@` | Pull request review |
| CI Guardian | 品質 | 失敗した check を flaky か実障害かに分類 | check 失敗、月曜 | CI failures |
| Sentinel | 品質 | セキュリティ担当。要件の脅威分析・設計のセキュリティレビュー・マージ前のセキュリティレビュー（security-review）と依存更新 | Planner・Conductor・Reviewer の `@`、PR マージ（後追い）、月曜 | Security check / Dependency updates |
| Release Captain | 出荷 | 出荷前の一覧、リリースノート草案、デプロイ要約 | 平日朝、依頼時、Webhook | Release readiness / notes / Deploy watch |
| Ops Scribe | 運用 | インシデントの時系列と振り返り草案、オンコール引き継ぎ | Intake の `@`（インシデント）、金曜 | Incident notes / On-call handoff |
| Doc Keeper | 運用 | コードとドキュメントのずれを検出し、選んだページだけ修正PR | 水曜 | Docs upkeep |
| PMO | 横断 | スタンドアップ、週次ブリーフィング、未レビュー作業、worktree 整理 | 平日朝、金曜午後 | Daily standup / Project briefing / Unreviewed agent work / Workspace cleanup |

開発ルームに 10 体全員を入れる（2026-11-25 から。`@` で渡せるのは同じルームの bot だけなので）。受け渡しと自動化はすべて開発ルームで動く。
出荷ルーム（Sentinel・Release Captain・Ops Scribe）は、人が出荷の相談をする場として残す。PMO はどちらにも入れず集約に専念させる。
ルームの会話は bot ごとに 1 本で、権限モードはルームの入力欄の Permissions（Replies で選んだ bot に効く）で Approve for me にする。

## 複数チームを並べるときの注意

- **利用枠**: Orca はモデルを持たない。bot とワーカーは全員が同じ Claude / ChatGPT / API の枠を食う。
  1チーム11体でも定時ジョブが重なると枠を使い切る。チームを増やす前に、各チームの定時を
  30分ずつずらす（`SETUP.md` の時刻表）。`Look around` は PMO だけに残す。
- **bot 間の分離が無い**: 同じホストの bot は互いに分離されていない。信頼度の違うチームは別ホストに置く。
- **名義**: GitHub のコメント・push・Project 更新はすべてオーナー名義で残る。
  チームが増えるほど人の作業と混ざるので、PR とコメントの冒頭に bot 名を入れる指示を外さない。
- **ホスト**: bot は置いたコンピューターが起きている間しか動かない。継続的デリバリーに使うなら
  常時稼働ホストに `orca serve service install` した Orca を置き、`orca environment add` でペアリングする。

## 設計書とのずれ

設計書の `gate-create` と `check --wait` は Orca v1.4.269 には無い / 禁止されている。
何をどう直したかは [VERIFY.md](VERIFY.md) に記録してある。Orchestration は実験的機能なので、
展開するたびに `orca skills get orchestration --full` と `bots/conductor.md` を照合する。

## テンプレートを直すときの注意

- **シェルは bash 3.2（macOS 既定）で動く。** `$VAR` の直後に全角文字を置くと、3.2 は
  全角のバイト列まで変数名として読む。`echo "（$DEFAULT_BRANCH）"` が
  `DEFAULT_BRANCH）: unbound variable` で落ちた。日本語の文に変数を埋めるときは必ず
  `${VAR}` と波括弧で囲む。
- **`updateProjectV2Field` は選択肢を丸ごと置き換える。** item が入っている Project に対して
  実行すると既存の値が消える。`setup-github.sh` は item 数を見て、0 件でなければ触らない。
- `scripts/*.sh` を直したら `bash -n` を通し、対象プロジェクトで 2 回続けて流して
  同じ結果になることを確かめる（どちらも何度流しても同じ結果になるように書いてある）。
- `tests/run.sh` で、構文の確認・判定フック（`scripts/bot-guard.py`）の試験・試しの設定でのレンダリングを流す。
  判定フックの振る舞いを変えるときは、先に `tests/bot-guard.sh` に 1 件足して期待と違うことを確かめてから直す。

## 記録を残す場所

- このリポジトリ = 全チーム共通の正。直したら各プロジェクトへ `render.sh` を再実行する。
- `VERIFY.md` = 設計書と実機のずれ、環境側の不足、試運転で確認することの一覧。
- 各プロジェクト側の `bots/` = レンダリング結果。手で直したら、同じ修正をこちらへ戻す。
- 設定ファイルと、どのプロジェクトにどの段階まで入れたかの台帳は、各自の置き場所（設定ファイルの隣など）に置く。
  このリポジトリには入れない（`team.*.config` は `.gitignore` で外してある）。

## ライセンス

[MIT](LICENSE)
