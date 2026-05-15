# pst — secure paste for AI coding agents

**Stop pasting your API keys into the chat.**

You know the moment when the agent says *"I need your Stripe key,"* and you... paste it, right into the conversation? 😬 And then you tell yourself you'll rotate it later, but then you don't. 🙈

`pst` is the dead-simple way out.

```bash
/pst STRIPE_API_KEY
```
Your value goes from clipboard → macOS Keychain. Your agent can use it without ever seeing the value. The chat never touches it. Profit.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash
```

That detects your shell's PATH, drops `pst` somewhere sensible, and — if it finds Claude Code or Codex — installs skill files so the agent knows when to reach for it. Idempotent. Re-run anytime to update.

Don't trust curl-piping to bash? Same install in two lines:

```bash
git clone https://github.com/amerry19/pst-cli.git
./pst-cli/install.sh
```

**Uninstall:**

```bash
curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash -s -- --uninstall
```

---

## The "Fuck It I'll Rotate Later" Tax

AI agents are excellent at writing code, but they need credentials to actually do anything useful. So every dev using Claude Code, Codex, Cursor, Aider, *whatever* hits this exact moment:

> Agent: "I need your GoDaddy API key to update DNS."
> You: *pastes it in chat*
> You (internally): "I'll rotate that later."

You don't. Nobody does. And now that key is:

- In your conversation history forever
- In whatever telemetry pipeline your agent's host runs
- In the Slack thread where you copy-pasted "this is so cool"
- Potentially in next year's training corpus
- Visible to anyone who screenshares your editor

The "fuck it" tax compounds. `pst` is what you reach for instead.

---

## How It Works

```
   ┌───────────┐                          ┌──────────────────┐
   │ Clipboard │ ─── pst paste NAME ───►  │ macOS Keychain   │
   └───────────┘                          │  (encrypted)     │
                                          └────────┬─────────┘
                                                   │
                                  pst exec NAME -- curl ...
                                                   │
                                                   ▼
                                          ┌──────────────┐
                                          │ child proc   │  ← agent sees this
                                          │ ($PST_VALUE) │     command's output,
                                          └──────────────┘     not the value
```

Three steps:

1. **Intake** — `pst paste NAME` reads your clipboard, trims whitespace, stores in macOS Keychain, clears the pasteboard.
2. **Use** — `pst exec NAME -- some-command` runs your command with the secret injected as `$PST_VALUE`. The agent sees the command's output, not the secret.
3. **Audit / clean** — `pst list` shows names (never values). `pst shape NAME` shows length + public prefix (`rnd_`, `sk-`, etc) — useful for verifying you stored the right *type* of thing. `pst rm NAME` deletes.

The chat never sees the value. Not the agent's context window. Not the transcript. Not your shell history.

---

## Why Keychain Instead of `.env`?

You might be thinking: *"my secrets already live in a `.env` file, why do I need this?"* Fair. Real differences:

| | `.env` | macOS Keychain |
|---|---|---|
| **Storage** | Plaintext on disk | AES-encrypted at rest, OS-managed |
| **Accidental git commit** | Common (`.gitignore` is imperfect) | Impossible — no file to commit |
| **Accidental agent grep** | Frequent — agents love to `cat .env` | Won't happen — secrets aren't in your filesystem |
| **Inspection** | Find the file, hope it's the right one | Native Keychain Access.app shows everything |
| **Lifecycle** | Sits in old project folders forever | Survives cleanups; `pst rm` to remove |
| **Backups** | Plaintext in your Time Machine | Encrypted in the keychain blob |

`.env` files are great for *config* (DATABASE_URL, FEATURE_FLAG_X). They were never designed for *secrets*. Keychain was.

---

## Commands

```
pst paste <NAME>                     Read clipboard → keychain, clear clipboard
pst set <NAME>                       Silent prompt for value (real terminal only)
pst get <NAME>                       Print value to stdout (use with pipe!)
pst exec <NAME> -- <CMD> [args]      Run CMD with secret as $PST_VALUE
pst exists <NAME>                    Quiet check (exit 0 = set, 1 = not)
pst shape <NAME>                     Safe diagnostic: length + public prefix
pst list                             Show stored secret names (never values)
pst rm <NAME>                        Delete a stored secret
pst rotate <NAME>                    Delete + re-set (terminal-only)
pst help                             Full help
```

`PST_SERVICE` env var scopes secrets to a custom keychain service name — useful for per-project isolation: `PST_SERVICE=my-app pst paste API_KEY`.

---

## Agent Integration

`pst` works from any shell, so any agent that can run shell commands can use it. The installer auto-installs skill files for:

- **Claude Code** — drops a `SKILL.md` into `~/.claude/skills/pst/` so the agent picks it up when you say things like *"set my Stripe key"* or `/pst STRIPE_KEY`.
- **Codex** — drops the same `SKILL.md` into `~/.codex/skills/pst/`. Codex's skill primitive mirrors Claude Code's, so one file works for both. Trigger by natural language (no `/pst` slash command in Codex): *"set my Render token"*, *"store this credential."* Restart Codex after install to pick up the skill.

Other agents work out of the box from the shell. If you'd like a first-class integration for Cursor, Aider, Continue, or another harness, [open an issue](https://github.com/amerry19/pst-cli/issues) and we'll add it.

---

## The Anti-Patterns This Stops

Specific failure modes `pst` is designed to prevent — collected from real-world LLM agent flows:

- ❌ Pasting an API key in chat "just for a sec." (Now it's in the transcript forever.)
- ❌ Storing a key to `.env` and trusting the agent never to `cat` or `grep` it.
- ❌ The agent printing partial chars of a secret "for diagnostic purposes." Use `pst shape` — it only shows length + the publicly-documented prefix (which is in the docs anyway).
- ❌ Capturing a secret into a shell variable that ends up in `set -x` debug output or exception traces.
- ❌ Pasting a token into your terminal with `read -s`, except the terminal isn't a real TTY so it reads from stdin you didn't realize was there.

If you've hit any of these — same.

---

## What This Does Not Do

Honest tradeoffs, owned:

- **macOS only right now.** Linux libsecret backend is on the roadmap. PRs welcome.
- **Headless / CI doesn't have a user keychain.** This is a developer-machine tool. For CI, use your cloud secrets manager of choice.
- **A compromised user account can read everything in their own keychain.** `pst` doesn't make you safer against `you` being compromised — only against accidental transcript leakage.
- **Doesn't sync across machines** unless you turn on iCloud Keychain (which encrypts the sync). That's a feature for most people; an annoyance for some.

---

## Threat Model

Things `pst` defends against:

- ✅ Chat-transcript exposure of secret values
- ✅ Agent-context-window exposure during normal flows
- ✅ Shell history leakage (no value ever lands in shell history)
- ✅ Accidental `.env` exposure (no file to leak)
- ✅ `set -x` / debug-output leakage (when used via `pst exec`)

Things `pst` does NOT defend against:

- ❌ A malicious agent with shell access can `pst get NAME` itself
- ❌ Operator-level OS compromise — if your Mac is owned, your keychain is owned
- ❌ A skill prompt-injection attack that convinces the agent to print a value (this is why the installed skill files have explicit `pst shape`-only diagnostic rules)
- ❌ Memory residue inside Node/Python processes that handled the value (inherent to those runtimes — minimize lifetime, but it's there)

---

## FAQ

### How do I stop leaking API keys to Claude Code, Cursor, or Codex?

Install pst. The skill files teach the agent to use `pst paste NAME` instead of asking you to paste in chat. The agent never sees the value; only the name of the secret.

### What about `.env` files? Don't they already solve this?

`.env` is plaintext on disk and gets `cat`'d or `grep`'d by AI agents constantly. They're great for *config* (DATABASE_URL, FEATURE_FLAG_X), but were never designed for secrets. macOS Keychain was. See [Why Keychain Instead of .env?](#why-keychain-instead-of-env) above for the full comparison.

### Can I use 1Password / Doppler / HashiCorp Vault with AI agents instead?

Yes, and those are great for **team** secret management. pst is a **local developer** tool — designed for the moment when you, alone at your laptop, need to hand a credential to an agent without it landing in the chat transcript. The patterns compose: store your team's source of truth in Vault, fetch individual values into pst when you need to use them locally with an agent.

### Does this work with MCP (Model Context Protocol) servers?

Yes. Any MCP that needs third-party API credentials can document `pst paste NAME` in its tool descriptions, then use `pst exec` to consume the value. The protocol itself doesn't change — pst sits between the user and the MCP runtime.

### Is `curl | bash` safe to run for this installer?

It's a real concern — never run an unfamiliar shell script unaudited. We've optimized `install.sh` for fast manual audit: ~260 lines, no obfuscation, an "auditor's tour" header that enumerates exactly which URLs are fetched and which directories are touched. If you'd rather not curl-pipe, the README's [Install](#install) section shows the equivalent `git clone` flow.

### What if I'm on Linux or Windows?

macOS only right now. Linux libsecret backend is on the roadmap — PRs welcome. Windows credential vault is further out. The CLI is intentionally a thin wrapper around the OS's native secrets API, so each platform port lives in one section of `bin/pst`.

### How is this different from prompt-injection defenses or LLM firewalls?

Different layer. Prompt-injection defenses prevent **malicious content** from reaching the LLM. pst prevents **the user's own credentials** from reaching the LLM's context. Both belong in a complete security posture; pst is the credential-handoff piece.

### Does pst protect against an attacker who already has shell access to my machine?

No. If your user account is compromised, the attacker can run `pst get NAME` on anything in the keychain. pst protects against **accidental** transcript leakage, not local OS compromise. Use FileVault, OS lock-screen, and good password hygiene for the latter.

### Does pst send any telemetry?

No. Search the source: `grep -E 'curl|wget|http|nc' bin/pst` shows zero network calls (matches in comments and examples only). The installer fetches exactly 3 files from `raw.githubusercontent.com` during install and nothing else thereafter.

---

## Roadmap

- [ ] Linux libsecret backend
- [ ] Homebrew tap (`brew install amerry19/pst/pst`)
- [ ] First-class Cursor `.cursorrules` integration
- [ ] First-class Aider `CONVENTIONS.md` integration
- [ ] Per-project scoping via `.pst-service` files (so the agent automatically uses `PST_SERVICE=$(cat .pst-service)`)
- [ ] Optional Sentry/Slack alerts on suspicious `pst get` patterns

---

## Contributing

Open an issue, send a PR. The CLI is a single ~250-line bash script — easy to read, easy to change.

```bash
git clone https://github.com/amerry19/pst-cli.git
cd pst-cli
./test/test_pst.sh   # runs ~50 integration tests against a disposable keychain namespace
```

If you're adding a new agent harness integration, drop a markdown file in `skills/<harness-name>.md` and update `install.sh` to detect + install it. The pattern is: detect the harness's config directory, render the skill into the right location, delimit with markers if appending to a shared file.

---

## License

MIT.

---

*Built by [Adam Merry](https://adammerry.com) while trying not to paste API keys into agent chats.*
