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
argument-hint: "<NAME> | list | rm | rotate"
license: MIT
metadata:
  author: Adam Merry
  version: "0.2.0"
  category: security
---

# pst — secure secret intake

## Argument routing

`/pst <args>` — first token decides the path:

- **Bare NAME** (anything not in the verb list) → clipboard paste flow. The common case.
- `list` / `rm NAME` / `rotate NAME` → user-facing CLI ops.
- `get NAME` / `exists NAME` / `exec NAME -- CMD` / `shape NAME` → agent-internal helpers.
- `paste NAME` → explicit form of bare NAME.
- `help` → CLI help.

Verbs: `get`, `exists`, `exec`, `list`, `ls`, `rm`, `remove`, `rotate`, `paste`, `set`, `shape`, `help`, `version`. Anything else is treated as a NAME.

## Slash flow (`/pst NAME`)

The user just copied something. Be fast.

1. **Run `pst paste <NAME>`** — overwrites silently if already set; that's intended. On non-zero exit (clipboard empty) tell them once: *"Clipboard looked empty. Copy and try `/pst <NAME>` again."* Don't pre-check with `pst exists` — it surfaces as a scary red exit-1 banner.

2. **If there's an implied follow-up** ("set my Stripe key and list customers") — chain straight into `pst exec STRIPE_KEY -- ...` and report the user-visible result. Don't pause to acknowledge.

   **If there's no follow-up** — one line: `Got it — NAME is set.` Stop. Don't call `pst shape` on the routine path — it adds a low-level tool box for no user benefit. Reserve `pst shape` for when the user explicitly asks ("is my key set? what shape?") or when diagnostic value is real. Never mention `pst exec` to the user — that's internal mechanism.

## Using a stored secret

- **`pst exec NAME -- CMD`** — runs CMD with `$PST_VALUE` set for the child only. Preferred.
- **`pst get NAME | consumer`** — only when the consumer reads stdin. Never `VAR=$(pst get NAME)` — leaks via `set -x`, exception traces, shell history.

## Project isolation

`PST_SERVICE=my-project pst ...` namespaces secrets per project. Use the repo name when the user is clearly scoped to one.

## Hard rules (no exceptions)

- ❌ **Don't ask the user to paste a value into chat.** Use `pst paste` (clipboard) or `pst set` (real terminal).
- ❌ **Don't run `pst set` from `!` bash** — needs a TTY. Use `pst paste`.
- ❌ **Don't print the value, any substring, hash, fingerprint, base64, hex, or any derived form.** Zero characters of the value ever appear in agent output.
- ❌ **Don't construct inspection commands** like `${PST_VALUE:0:4}`, `${#PST_VALUE}`, `md5 $PST_VALUE` inside `pst exec`. Use `pst shape` for any diagnostic need.
- ❌ **Don't write the value** to log files, temp files, `ps`-visible args, or env vars that outlive the subshell.

## Diagnostic toolkit

| Question | Right tool |
|---|---|
| Is it set? | `pst exists NAME` |
| Length / shape? | `pst shape NAME` |
| Does it actually work? | `pst exec NAME -- <api-call-with-output-suppressed>` and check the HTTP code |

## Repo

https://github.com/amerry19/pst-cli
