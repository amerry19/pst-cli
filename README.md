# pst — secure paste for AI coding agents

**Stop pasting your API keys into the chat.**

`pst` is a small macOS CLI that takes a secret from your clipboard, stores it in the Keychain, and hands it to commands through env-var injection — so the value stays out of your agent's chat.

```bash
# in your shell:
pst paste STRIPE_API_KEY
pst exec STRIPE_API_KEY -- curl -H "Authorization: Bearer $PST_VALUE" https://...

# or via your agent:
/pst STRIPE_API_KEY     # Claude Code
"set my Stripe key"     # Codex (natural language)
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/v0.1.0/install.sh | bash
```

Pinned to the `v0.1.0` tag. Auto-installs skill files for Claude Code and Codex if it finds them. Idempotent; `--uninstall` reverses cleanly.

Prefer not to curl-pipe-bash? The installer is ~280 lines with an auditor's tour at the top — or:

```bash
git clone --branch v0.1.0 https://github.com/amerry19/pst-cli.git
./pst-cli/install.sh
```

## How it works

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

Three primitives:

- **`pst paste NAME`** — read clipboard, trim, store in Keychain, clear clipboard.
- **`pst exec NAME -- CMD`** — run `CMD` with the value as `$PST_VALUE`. The agent sees the command's output, not the value.
- **`pst shape NAME`** — safe diagnostic; prints length + known public prefix only (never content).

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

`PST_SERVICE` scopes secrets per project: `PST_SERVICE=my-app pst paste API_KEY`.

## Agent integration

The installer drops the same `SKILL.md` into whichever harness it finds:

- **Claude Code** → `~/.claude/skills/pst/`. Trigger with `/pst NAME` or natural language ("set my Stripe key").
- **Codex** → `~/.codex/skills/pst/`. Trigger with natural language; restart Codex after install.

Any agent that can run shell commands can use `pst` regardless. For first-class skill support in another harness (Cursor, Aider, Continue, …), [open an issue](https://github.com/amerry19/pst-cli/issues).

## Threat model

**Defends against:**

- Chat-transcript exposure of secret values
- Agent-context-window exposure during cooperative flows
- Shell history leakage
- `.env` file leakage — no file to leak (and agents `cat .env` constantly)
- `set -x` / debug-output leakage when used via `pst exec`

**Does not defend against:**

- A malicious agent with shell access running `pst get NAME` itself
- OS-level compromise — if your Mac is owned, your keychain is owned
- Skill prompt-injection that convinces the agent to print a value
- Memory residue in language runtimes that handled the value

Not a team-secret manager, and not for CI. Use 1Password, Vault, Doppler, etc. for team source-of-truth or headless environments. `pst` is what you reach for when you, locally, need to hand a value to an agent.

No telemetry — `grep -E 'curl|wget|http|nc' bin/pst` returns zero non-comment matches.

## Roadmap

- [ ] Linux libsecret backend
- [ ] Homebrew tap
- [ ] First-class Cursor / Aider integrations
- [ ] Per-project scoping via `.pst-service` files

## Contributing

```bash
git clone https://github.com/amerry19/pst-cli.git
cd pst-cli
./test/test_pst.sh   # 50 integration tests against a disposable keychain namespace
```

To add a harness integration: drop a skill file in `skills/<harness>.md` and update `install.sh` to detect + install it.

## License

MIT.

---

*Built by [Adam Merry](https://adammerry.com) while trying not to paste API keys into agent chats.*
