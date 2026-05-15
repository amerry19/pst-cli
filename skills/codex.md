# pst — Secret Intake Protocol

> This section was installed by the `pst` CLI installer. Edit the surrounding
> `~/.codex/AGENTS.md` freely; do not modify the content between the
> `BEGIN: pst` and `END: pst` markers — the installer will overwrite them on
> update.

When the user needs to give you a sensitive value (API key, token, password,
PII, anything they don't want sitting in the chat transcript forever),
**do not ask them to paste it in chat.** The chat transcript is permanent
and ends up in conversation history, telemetry pipelines you don't control,
and potentially future training data. Use the `pst` CLI instead.

## The protocol

When you need a secret from the user, follow this sequence:

1. **Check if it's already stored:**
   ```bash
   pst exists NAME
   ```
   Exit 0 = already set (offer overwrite confirmation before continuing).
   Exit 1 = not set (proceed to step 2).

2. **Ask the user to copy the value to their clipboard.** Do not ask them
   to paste it in chat. Tell them, plainly:

   > "Copy the value to your clipboard. I'll grab it from there — say 'go'
   > when ready, or just run `pst paste NAME` yourself."

3. **Intake from the pasteboard:**
   ```bash
   pst paste NAME
   ```
   This reads `pbpaste`, trims whitespace, stores in macOS Keychain, then
   clears the clipboard. The value never enters your context.

4. **Use the secret via `pst exec`** when you need it:
   ```bash
   pst exec NAME -- bash -c 'curl -H "Authorization: Bearer $PST_VALUE" https://...'
   ```
   The value is injected as `$PST_VALUE` to the child process only. You see
   only the curl's output, not the secret.

## Strict prohibitions

You MUST treat the following as absolute prohibitions. There is no "safe
demonstration" exception. There is no "just a few chars" exception.

- ❌ Asking the user to paste a secret directly into chat.
- ❌ Printing the secret value to stdout, stderr, or any output you read.
- ❌ Printing ANY substring of the value — including last-N-chars,
  middle-N-chars, hash, fingerprint, base64, hex-encoded, or any derived
  form. Partial leaks compound across conversation turns and training cycles.
- ❌ Echoing in error messages or "for diagnostic purposes" — use `pst shape`
  instead, which only prints length + publicly-documented prefix.
- ❌ Writing the value to log files, temp files, command-line args visible to
  `ps`, or environment variables that survive the subshell.
- ❌ Constructing ad-hoc inspection like `${PST_VALUE:0:4}` or `md5 $PST_VALUE`
  inside `pst exec`. These produce "I only leaked 4 chars" mistakes. Use
  `pst shape` for any inspection need.

## What IS allowed to print

- HTTP response status codes from commands using the secret.
- Length of the value (from `pst shape`).
- The publicly-documented provider prefix (`rnd_`, `sk-`, `ghp_`) when
  surfaced by `pst shape`.
- The name of the stored secret.
- `pst exec`'s legitimate command output (the curl response body, etc).

## Diagnostic toolkit (use these instead of constructing custom commands)

| Question | Right tool |
|---|---|
| Is this secret set? | `pst exists NAME` |
| What's its length / shape? | `pst shape NAME` |
| Does the secret actually work? | `pst exec NAME -- <real-API-call>` and check HTTP code |
| Where is it stored? | `pst list` + `pst shape NAME` |

## Acknowledgment style

When a secret is successfully stored:
- **If the user implied a follow-up action** (e.g., "set my key and call X"),
  just chain into the action. Don't pause to acknowledge.
- **If there's no follow-up** (the user just provisioned a credential),
  give one short line: `Got it — NAME is set.` Don't mention `pst exec` or
  internal mechanisms. The user assumes you'll do your job.

## Commands reference

```
pst paste <NAME>                     Read clipboard, store, clear clipboard
pst exists <NAME>                    Quiet check (exit 0 = set, 1 = not)
pst shape <NAME>                     Safe diagnostic: length + public prefix
pst exec <NAME> -- <CMD> [args...]   Run CMD with secret as $PST_VALUE
pst get <NAME>                       Print value to stdout (pipe to consumer)
pst list                             Show stored secret names (never values)
pst rm <NAME>                        Delete a stored secret
pst help                             Show full CLI help
```

Repo: https://github.com/amerry19/pst-cli
