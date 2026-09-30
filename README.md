# AI CLI Status Line

Claude Code と Codex CLI のステータスライン設定です。
特別なフォントは不要で、標準的なターミナルでそのまま使えます。

*Status line setups for Claude Code and Codex CLI. No special fonts required.*

## Claude Code

```
Opus 5.5 v2.1.285 [high] │ █░░░░░░░░░ 12% (123.0k/1.0M) │ $1.2345 │ +10 -3
⏱ 5h  ▰▰▰▰▰▰▰▱▱▱  72% Resets 8:45pm JST
📅 7d  ▰▰▱▱▱▱▱▱▱▱  18% Resets Oct 6 at 4am JST
```

| 行 | 内容 |
| - | - |
| 1 | モデル名・バージョン・effort（⚡fast モード時）│ コンテキスト使用率バー（使用トークン/上限）│ セッションのコスト │ 追加/削除行数 |
| 2 | 5 時間レート制限の使用率とリセット時刻 |
| 3 | 7 日間レート制限の使用率とリセット時刻 |

使用率 50% 以上で黄色、80% 以上で赤になります。

### 必要なもの

- `bash`, `jq`, `awk`, `curl`
- macOS / Linux
- 5h / 7d の表示は claude.ai の Pro / Max プランのみ（Claude Code がレート制限情報を渡すのはこのプランだけのため）

### インストール

```bash
git clone https://github.com/GenSSK/ai-cli-statusline.git
cp ai-cli-statusline/claude/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

`~/.claude/settings.json` に以下を追加します。

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

### 設定（環境変数・任意）

| 変数 | 既定値 | 説明 |
| - | - | - |
| `STATUSLINE_TZ` | システムのタイムゾーン | リセット時刻の表示タイムゾーン（例: `Asia/Tokyo`） |
| `STATUSLINE_PROBE` | `1` | `0` にするとフォールバックの API 問い合わせを無効化（下記参照） |
| `STATUSLINE_CACHE_FILE` | `/tmp/claude-statusline-ratelimits.json` | レート制限のキャッシュファイル |

環境変数は `settings.json` の command で渡せます。

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
   キャッシュも無いときは、Claude Code のログイン情報（macOS はキーチェーン、Linux は `~/.claude/.credentials.json`）を使って Haiku に 1 トークンだけのリクエストを送り、レスポンスヘッダから使用率を読み取ります。
   6 分に 1 回までに制限していますが、わずかに使用量を消費します。
   不要な場合は `STATUSLINE_PROBE=0` で無効にできます。

どの経路でも、表示する % は 0〜100 に収めます。

## Codex CLI

Codex CLI（0.158.0 で確認）はステータスラインに任意のスクリプトを使えず、組み込み項目を並べる方式です。
[`codex/config.toml`](codex/config.toml) の `[tui]` の設定を `~/.codex/config.toml` に追記してください。
（すでに `[tui]` がある場合は、その中にキーを追加します。）

```toml
[tui]
status_line = [
  "model-with-reasoning",
  "fast-mode",
  "context-used",
  "estimated-thread-cost",
  "five-hour-limit",
  "weekly-limit",
  "git-branch",
  "current-dir",
]
status_line_use_colors = true
```

Codex 内で `/statusline` を実行すると、項目を対話的に選ぶこともできます。

## License

[MIT](LICENSE)
