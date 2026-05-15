---
name: pst
description: >-
  Accept sensitive values (API keys, tokens, credentials, PII, anything the
  user shouldn't paste into chat) from the user without the value ever
  entering the agent's chat context. Uses the `pst` CLI which stores values
  in macOS Keychain and exposes them via `pst exec` (env var injection) or
  `pst get` (pipe to consumer).

  TRIGGER whenever the agent needs a secret value to complete a task. Common
  signals: "set X env var", "I need to give you my API key", "paste my token",
  "store this credential", "wire up GoDaddy / Stripe / OpenAI / Anthropic key",
  any time the agent would otherwise ask the user to paste a sensitive value
  into the conversation.

  Trigger terms: secret, credential, API key, token, paste, env var, sensitive
  value, set this value, configure this key.
license: MIT
metadata:
  author: Adam Merry
  version: "0.2.0"
  category: security
---

# pst — secure secret intake without chat-context leakage

## Argument interpretation (CRITICAL — read first)

When this skill is invoked, the agent must interpret the args based on
the first token:

- `/pst NAME` (single arg, NOT one of the verbs below) → **default to the
  paste-from-clipboard flow** described in the next section. This is the
  fast path and the overwhelmingly common case. Don't ask the user to
  retype the verb.
- `/pst get NAME` → read the value (rarely used by the agent directly;
  prefer `exec`)
- `/pst exists NAME` → quiet check
- `/pst exec NAME -- CMD` → run CMD with `$PST_VALUE` injected
- `/pst list` → show stored names
- `/pst rm NAME` → delete
- `/pst rotate NAME` → delete + re-paste from clipboard
- `/pst paste NAME` → explicit form of the default paste flow (same as
  bare `/pst NAME`)
- `/pst help` → show CLI help

The verbs are: `get`, `exists`, `exec`, `list`, `ls`, `rm`, `remove`,
`rotate`, `paste`, `set`, `help`, `version`. Any first token NOT in this
list is treated as a NAME for the paste flow.

## Slash-command flow (the primary UX in Claude Code)

When the user invokes this skill as `/pst NAME`, assume the value is
already on their clipboard. App developers don't type slash commands
speculatively — they're in flow, they just copied something. The agent's
job is to be fast and not add friction.

### 1. Check if the secret is already set (footgun protection)

```bash
! pst exists <NAME>
```

- Exit 0 → already set. Ask "Already have `<NAME>` stored. Overwrite? y/n"
  and wait. This IS worth confirming — overwriting a working secret is
  destructive. If "n", abort and acknowledge.
- Exit 1 → not set. Skip directly to step 2.

### 2. Intake from the pasteboard immediately

```bash
! pst paste <NAME>
```

Do NOT ask "are you copied yet?" The user just typed a slash command —
they're ready. Just try the paste.

`pst paste` reads the clipboard, auto-trims leading/trailing whitespace,
rejects empty/whitespace-only values, stores in Keychain, then clears
the pasteboard. The value never enters the chat (only the command name).

- Exit 0 → stored. Proceed to step 3.
- Exit non-zero → clipboard was empty or whitespace. Tell the user
  plainly: "Clipboard looked empty. Copy the value and try `/pst <NAME>`
  again." Don't escalate; this is a recoverable user action, not an
  error to dwell on.

### 3. Acknowledge briefly, then DO THE THING

The user just gave the agent a credential. Their mental model is "agent
has it, agent does the thing." So:

**If there's an implied follow-up action** (the user said something like
"set my Stripe key and use it to list customers"), DO NOT pause to
narrate the storage. Just continue with the task:

> [no confirmation message — go straight to `pst exec STRIPE_KEY -- ...`
> and report whatever the user actually asked for]

**If there's no follow-up** (e.g., the user just typed `/pst NAME` to
provision a credential for later use), give a one-line acknowledgment
and stop. Don't mention `pst exec` — that's the agent's internal
mechanism, not the user's homework. Don't editorialize:

> "Got it — `RENDER_API_TOKEN` is set."

Or, if you want to be a little more informative without leaking
mechanism, run `pst probe` and surface the shape/length as
transparency:

> "Got it — `RENDER_API_TOKEN` (32 chars, Render-style)."

That's it. No "I can use it via `pst exec` whenever you need it." No
"ready to use." The user assumes the agent will do its job; reminding
them of the mechanism is undertone-condescending and adds friction.

### What NOT to do

- ❌ "Tell me when copied." (User is in flow; just paste.)
- ❌ "Does this look right?" (Agent has no basis to judge.)
- ❌ "Ready to use via `pst exec` whenever you need it." (Implementation
   detail; the user doesn't care HOW the agent uses it.)
- ❌ Verbose confirmation prompts. One line max.
- ❌ Multi-step `pst exists → pst paste → pst exists → pst probe`
  chains. Two commands (`exists`, then `paste`), three at the absolute
  most if you want the probe summary. Stop there.
- ❌ Pausing to acknowledge when there's an implied next action. Just
   chain into the next call.

## Using a stored secret

Two patterns, both leakage-safe:

### `pst exec` — inject as env var into a child process (preferred)

```bash
! pst exec RENDER_API_TOKEN -- bash -c 'curl -H "Authorization: Bearer $PST_VALUE" https://api.render.com/v1/services'
```

The secret lives in `$PST_VALUE` for the duration of the child process
only. The agent sees the curl's stdout, not the secret.

### `pst get` — pipe to a stdin-reading consumer

```bash
! pst get GODADDY_API_KEY | some-tool --read-stdin
```

Only use when the consumer is explicitly reading stdin. Avoid
`VAR=$(pst get NAME)` — that captures the value into a shell var that
can leak via `set -x`, exception traces, or shell history.

## Existence check (decision support)

When the agent is unsure whether a credential is already configured, use
`pst exists NAME` — it's quiet (no output) and returns exit 0/1. Use it
to decide whether to ask the user to provide a value or proceed directly.

## Per-project scoping

By default, secrets live under the `pst` keychain service namespace. For
project isolation, set `PST_SERVICE`:

```bash
! PST_SERVICE=my-project pst paste API_KEY
! PST_SERVICE=my-project pst exec API_KEY -- some-command
```

The agent should pick a project-specific `PST_SERVICE` when the user is
working in a clearly-scoped repo (e.g., the repo name).

## Anti-patterns to avoid (HARD RULES — no exceptions)

The agent MUST treat the following as absolute prohibitions. There is no
"safe demonstration" exception. There is no "just a few chars" exception.

### Prohibited intake patterns

- ❌ Asking the user to paste a secret value directly into the chat.
   Always route through `pst paste` (clipboard) or `pst set` (real
   terminal).
- ❌ Running `pst set` from inside Claude Code's `!` bash field. `read -s`
   needs a real TTY. Use `pst paste` instead.
- ❌ Storing the secret to a `.env` file the agent might later `cat` or
   `grep`.

### Prohibited output patterns (the leak-prevention rules)

- ❌ Printing the secret value to stdout, stderr, or any output the agent
   reads. Period.
- ❌ Printing ANY substring of the value — including:
   - last N chars / suffix
   - middle N chars
   - every-other-char
   - hash, fingerprint, base64, hex-encoded, or any derived form
- ❌ Echoing in error messages, exception traces, or "for diagnostic
   purposes" — diagnostics MUST use `pst probe` (see below).
- ❌ Writing the value into log files, temp files, command-line args
   visible to `ps`, environment variables that survive the subshell, or
   anywhere else where it could be observed by a later command.
- ❌ Constructing ad-hoc inspection commands like `\${PST_VALUE:0:4}`,
   `\${PST_VALUE: -4}`, `\${#PST_VALUE}`, `md5 \$PST_VALUE`, etc. when
   running under `pst exec`. These are exactly the pattern that produces
   "I only leaked 4 chars" mistakes. Use `pst probe` instead.

### What IS allowed to print

To be exhaustive and remove ambiguity:

| Output | Allowed? |
|---|---|
| HTTP response status codes from commands using the secret | ✅ |
| Length of the value (when fetched via `pst probe`) | ✅ |
| Whether the value is set (boolean from `pst exists`) | ✅ |
| The publicly-documented provider prefix (e.g. `rnd_`, `sk-`, `ghp_`) — only when surfaced by `pst probe` | ✅ |
| The name of the stored secret | ✅ |
| The service namespace | ✅ |
| `pst exec`'s stdout when it's the legitimate command output (curl result, etc.) | ✅ |

Everything else: NO.

### Why these rules exist

A "small" partial leak compounds across multiple turns of conversation
and across model training cycles. Four chars of a random token reduces
the brute-force search space measurably. Eight chars reduces it
significantly. Sixteen renders the token effectively guessable. The only
defensible policy is: zero characters of the value ever appear in the
agent's output, full stop.

### Diagnostic toolkit (use these instead of constructing custom commands)

When the agent needs to inspect or diagnose:

| Question | Right tool |
|---|---|
| Is this secret set? | `pst exists NAME` |
| What's its length / shape? | `pst probe NAME` |
| Does it look like a Render / OpenAI / etc. token? | `pst probe NAME` (the `shape:` line) |
| Does the secret actually work? | `pst exec NAME -- <real-API-call-with-output-suppressed>` and look at the HTTP code |
| Where is it stored? | `pst list` + `pst probe NAME` |

## Commands reference

```
pst set <NAME>                       Silent prompt (real terminal only)
pst paste <NAME>                     Read pasteboard, store, clear clipboard
pst get <NAME>                       Print value to stdout (pipe carefully)
pst exists <NAME>                    Quiet check (exit 0 = set, 1 = not)
pst exec <NAME> -- <CMD> [args...]   Run CMD with secret as $PST_VALUE
pst list                             Show stored secret names (never values)
pst rm <NAME>                        Delete a stored secret
pst rotate <NAME>                    Delete + re-set (terminal-only)
pst help                             Show full help
```

## Repo

https://github.com/amerry19/pst-cli
