# cc-statusline

A status line for [Claude Code](https://code.claude.com/docs/en/statusline) showing the four things that actually stop you working.

```
🤖 Opus 5 (high) │ 🧠 8% 17k/200k │ ⏳ 5h 23.5% 1h00m │ 📅 7d 41.2% 2d
```

| | | |
|---|---|---|
| 🤖 | **Model** | Which model you're on, plus reasoning effort — easy to lose track of after `/model` or `/effort`. |
| 🧠 | **Context** | Percent used and raw tokens: keep going, `/compact`, or start fresh. |
| ⏳ | **5h limit** | How much of the 5-hour window you've spent, and when it resets. |
| 📅 | **7d limit** | The same for the week, so you see it coming. |

Percentages turn yellow at 60% and red past 75% (context) or 80% (limits). Anything Claude Code doesn't send is dropped from the line, never shown as `0%`.

## Why this one

Most Claude Code status lines are *projects* — an npm or pip package, a Node or Python runtime, a config format, sometimes a daemon holding state between turns.

This is one shell script on the `statusLine` hook Claude Code already gives you. Nothing to install, no runtime, nothing running that Claude Code didn't start.

## Install

**1. Get the script** — macOS, Linux, or Git Bash on Windows:

```bash
mkdir -p ~/.claude
curl -fsSL https://github.com/binoyPeries/cc-statusline/releases/latest/download/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

That pulls the latest release. To pin a version, swap `latest/download` for `download/v0.1.0`; to track the tip of `main`, use `https://raw.githubusercontent.com/binoyPeries/cc-statusline/main/statusline.sh` instead.

**2. Point `settings.json` at it** — `~/.claude/settings.json` for every project, or `.claude/settings.json` inside one repo for just that repo:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Start a new session and it's there.

> **Windows needs Git Bash** ([Git for Windows](https://git-scm.com/download/win)) or WSL. Without one, Claude Code falls back to PowerShell, which can't run a Bash script — you get an empty status line and no error. *A PowerShell version is coming.* Use forward slashes in the path (`C:/Users/you/...`); Git Bash treats backslashes as escapes and fails silently.

## Update

Same command as step 1 — it overwrites the script in place, and `settings.json` doesn't change:

```bash
curl -fsSL https://github.com/binoyPeries/cc-statusline/releases/latest/download/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

`./statusline.sh --version` tells you what you're on; the [latest release](https://github.com/binoyPeries/cc-statusline/releases/latest) tells you whether that's current. Changes take effect on the next session.

## Configuration

Environment variables, set inline in the command:

```json
"command": "CCSL_ICONS=nerd ~/.claude/statusline.sh"
```

or in `~/.config/cc-statusline/config.sh`:

| Variable | Default | Notes |
|---|---|---|
| `CCSL_SEGMENTS` | `model context five_hour seven_day` | Which segments to show, in order. Drop any you don't want. |
| `CCSL_EFFORT` | `auto` | `never` hides the effort level next to the model. |
| `CCSL_ICONS` | `emoji` | `emoji`, `nerd` ([Nerd Font](https://www.nerdfonts.com/) required), `unicode`, or `none`. |
| `CCSL_COLOR` | `auto` | `never` turns off color. `NO_COLOR` is honored too. |
| `CCSL_SEP` | ` │ ` | Separator between segments. |
| `CCSL_WARN` | `60` | Percent at which a meter turns yellow. |
| `CCSL_CRIT_CTX` | `75` | Percent at which context turns red. |
| `CCSL_CRIT_LIMIT` | `80` | Percent at which a rate limit turns red. |
| `CCSL_CONFIG` | `~/.config/cc-statusline/config.sh` | Where to look for the config file. |

Preview any combination without launching Claude Code: `./statusline.sh --demo`.

## Good to know

- **Rate limits need a Pro or Max plan.** Claude Code doesn't send them on API-key auth, and they only arrive after a session's first response — as does the context data.
- **Effort shows only on models that support it.**
- **`jq` is optional.** Used if you have it, otherwise the script parses the JSON itself.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing shows up | Check `chmod +x` and the path in `settings.json`, then try `./statusline.sh --demo` |
| Nothing on Windows | Git Bash isn't installed, so PowerShell is trying to run a Bash script — install [Git for Windows](https://git-scm.com/download/win) and restart |
| No rate limits | API-key auth, or before the first response — check `/usage` for your plan |
| Garbled characters | Your font lacks the glyphs: `CCSL_ICONS=unicode` or `none` |
| Colors look off | They come from your terminal theme; `CCSL_COLOR=never` turns them off |

## Future work

- **`--check` and `--update`.** Releases are tagged now, but noticing a new one and installing it is still on you — re-run the `curl` and compare `--version` by eye. The plan is a `--check` / `--update` pair: one asks whether a newer release exists, the other fetches it and replaces the script in place, so updating is a command rather than a habit.
- **Windows without Git Bash.** A PowerShell port, so `statusLine` works against the shell Claude Code already falls back to instead of silently rendering nothing.

## Contributing

Directory, git branch, session cost and the rest were left out because they didn't make my top four, not because they're hard to add. `CCSL_SEGMENTS` reorders what's already there, and a new segment is a small function alongside the existing ones.

`./statusline.sh --demo` feeds the script a sample payload and prints the line, so you can iterate on a segment without launching Claude Code. Issues and pull requests welcome.

## License

MIT — see [LICENSE](LICENSE).
