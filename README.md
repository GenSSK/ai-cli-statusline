# AI CLI Status Line

Claude Code と Codex CLI のステータスライン設定です。
特別なフォントは不要で、macOS / Linux / Windows で使えます。

*Status line for Claude Code and Codex CLI. No special fonts required. Works on macOS, Linux and Windows.*

```
Opus 5.5 v2.1.285 [high] │ █░░░░░░░░░ 12% (123.0k/1.0M) │ $1.2345 │ +10 -3 │ 3f2a9c1e-8b4d-4e6f-a1b2-c3d4e5f60718        ~/a/status_line
⏱ 5h  ▰▰▰▰▰▰▰▱▱▱  72% Resets 8:45pm JST
📅 7d  ▰▰▱▱▱▱▱▱▱▱  18% Resets Oct 6 at 4am JST
```

## インストール（ワンライナー）

お使いの OS のコマンドを 1 行実行するだけです。
Claude Code と Codex CLI の両方を設定します（Codex が入っていなければ Codex はスキップ）。

### macOS / Linux / WSL

ターミナルで実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.sh | bash
```

### Windows

**PowerShell** で実行します。

```powershell
irm https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.ps1 | iex
```

インストール後、Claude Code / Codex を再起動すると表示されます。

### 事前に必要なもの

| OS | 必要なもの | 入れ方 |
| - | - | - |
| macOS | `jq` | `brew install jq` |
| Linux / WSL | `jq`, `curl` | `sudo apt install jq curl`（Debian/Ubuntu）<br>`sudo dnf install jq curl`（Fedora）<br>`sudo pacman -S jq curl`（Arch） |
| Windows | Git for Windows（Git Bash）, `jq` | `winget install Git.Git`<br>`jq` は無ければインストーラが `winget` で自動で入れます |

- Windows 版 Claude Code は、ステータスラインのコマンドを **Git Bash** で実行します。Claude Code を使っていれば、通常は Git for Windows はすでに入っています。
- WSL の中で Claude Code を使っている場合は、Windows ではなく「macOS / Linux / WSL」のコマンドを **WSL のターミナルで**実行してください。

### オプション

Claude Code だけ、または Codex だけ入れたい場合:

```bash
# macOS / Linux / WSL
curl -fsSL https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.sh | bash -s -- --no-codex
curl -fsSL https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.sh | bash -s -- --no-claude
```

```powershell
# Windows
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.ps1))) --no-codex
```

### インストーラがすること

| 対象 | 変更内容 |
| - | - |
| Claude Code | `~/.claude/statusline.sh` を配置し、`~/.claude/settings.json` の `statusLine` を設定（他の設定はそのまま） |
| Codex CLI | `~/.codex/config.toml` の `[tui]` に `status_line` と `status_line_use_colors` を追加（他の設定はそのまま） |

- 既存のファイルを変更するときは、同じ場所に `*.bak-日時` としてバックアップを作ります。
- 何度実行しても大丈夫です（設定済みなら変更しません）。
- Codex にすでに独自の `status_line` がある場合は上書きせず、メッセージだけ出します。
- `CLAUDE_CONFIG_DIR` / `CODEX_HOME` を設定している場合はそちらに入れます。

### アンインストール

- Claude Code: `~/.claude/settings.json` から `statusLine` を削除し、`~/.claude/statusline.sh` を消す
- Codex CLI: `~/.codex/config.toml` の `[tui]` から `status_line` と `status_line_use_colors` の 2 行を消す

（バックアップ `*.bak-日時` を元の名前に戻しても元通りになります。）

## Claude Code 版

| 行 | 内容 |
| - | - |
| 1 | モデル名・バージョン・effort（fast モード時は ⚡fast）│ コンテキスト使用率バー（使用トークン/上限）│ セッションのコスト │ 追加/削除行数 │ セッション ID … 右端に現在のディレクトリ（fish 風） |
| 2 | 5 時間レート制限の使用率とリセット時刻 |
| 3 | 7 日間レート制限の使用率とリセット時刻 |

- 使用率 50% 以上で黄色、80% 以上で赤になります。
- セッション ID は `claude --resume <セッションID>` でそのセッションを再開するときに使えます。
- ディレクトリは fish シェル風に、途中のフォルダを 1 文字に省略します（`~/ai-global/status_line` → `~/a/status_line`、`~/.config/fish` → `~/.c/fish`）。画面幅が足りないときは表示しません。
- 5h / 7d は claude.ai の **Pro / Max プラン**でのみ表示されます（API キー利用時は `--%`）。

### 設定（環境変数・任意）

| 変数 | 既定値 | 説明 |
| - | - | - |
| `STATUSLINE_TZ` | システムのタイムゾーン | リセット時刻の表示タイムゾーン（例: `Asia/Tokyo`） |
| `STATUSLINE_PROBE` | `1` | `0` にするとフォールバックの API 問い合わせを無効化（下記参照） |
| `STATUSLINE_RIGHT_MARGIN` | `4` | ディレクトリ表示の右端の余白（桁数）。右端で折り返す・寄りすぎる場合に調整 |
| `STATUSLINE_CACHE_FILE` | `/tmp/claude-statusline-ratelimits.json` | レート制限のキャッシュファイル |

`~/.claude/settings.json` の command で指定できます。

```json
"command": "STATUSLINE_TZ=Asia/Tokyo bash ~/.claude/statusline.sh"
```

### レート制限の取得方法

1. **Claude Code から受け取る値（通常はこれ）**
   Claude Code が stdin で渡す `rate_limits.five_hour` / `rate_limits.seven_day` を使います。
2. **キャッシュ**
   セッション開始直後など、1 の値がまだ無いときは直近の値を使います。
   リセット時刻を過ぎた値は古い枠のものなので捨てます。
3. **API 問い合わせ（フォールバック）**
   キャッシュも無いときは、Claude Code のログイン情報（macOS はキーチェーン、Linux / Windows は `~/.claude/.credentials.json`）を使って Haiku に 1 トークンだけのリクエストを送り、レスポンスヘッダから使用率を読み取ります。
   6 分に 1 回までに制限していますが、わずかに使用量を消費します。
   不要な場合は `STATUSLINE_PROBE=0` で無効にできます。

どの経路でも、表示する % は 0〜100 に収めます。

## Codex CLI 版

Codex CLI（0.158.0 で確認）はステータスラインに任意のスクリプトを使えず、組み込み項目を並べる方式です。
インストーラは次の設定を `~/.codex/config.toml` に追加します（中身は [`codex/config.toml`](codex/config.toml)）。

```toml
[tui]
status_line = ["model-with-reasoning", "fast-mode", "context-used", "estimated-thread-cost", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]
status_line_use_colors = true
```

Codex 内で `/statusline` を実行すると、項目を対話的に並べ替え・変更できます。

## 手動インストール

ワンライナーを使わない場合:

```bash
git clone https://github.com/GenSSK/ai-cli-statusline.git
cd ai-cli-statusline
bash install.sh          # Windows では Git Bash で実行
```

## License

[MIT](LICENSE)
