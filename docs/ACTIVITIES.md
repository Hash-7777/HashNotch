# Live activities, and AI finish alerts

macOS has no system API to read another app's live activity — that exists only
on iPhone. So HashNotch reads a small local file that any app, script or
Shortcut can write, and renders whatever is in it.

That file is the whole interface. Nothing here needs HashNotch to know
anything about the tool posting to it.

---

## The feed

`~/.hashnotch/activities.json` — an array of objects:

```json
[
  {
    "id": "order-1",
    "icon": "bicycle",
    "title": "Food delivery",
    "subtitle": "Rider on the way",
    "progress": 0.6,
    "endsAt": "2026-07-21T21:30:00Z"
  }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Required. Activities merge by it, so posting again replaces your own row and leaves everyone else's alone. |
| `title` | Required. |
| `icon` | Any SF Symbol name. Falls back to a generic badge. |
| `subtitle` | A second line in the panel, dimmed beside the title on the strip. |
| `progress` | `0`–`1`. Draws a bar. |
| `endsAt` | ISO 8601. Drives a live countdown, and the row disappears on its own when it passes. |
| `dismissAfter` | Seconds, from 1 to 30 — anything longer is brought back to 30. For something that **already happened**: no timer is drawn and the notice leaves by itself. |
| `image` | Path to a logo shown instead of the symbol. |
| `app` | Path to an installed `.app` — the row becomes clickable and brings it forward. |

### Two kinds

A **countdown** is something still happening, and shows its time left — use
`endsAt`. A **notice** is something that already finished — use `dismissAfter`
instead. A number ticking down beside the word "finished" only ever asked you to
watch something that was already over.

### From the shell

```sh
./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
./scripts/post-activity.sh --notice 3 "Build finished" "release" hammer
./scripts/post-activity.sh --clear
```

### It is treated as untrusted

Anything running as you can write this file, so nothing in it is taken on
trust: the file is capped at 256 KB and 8 activities, every string is
length-limited, `progress` is clamped, a logo is refused unless it is a readable
image under 4 MB, and `app` must be a real `.app` bundle **inside a standard
applications folder**, opened only when you click the row. See
[SECURITY.md](../SECURITY.md).

---

## Claude Code

One command wires it up:

```sh
./scripts/install-claude-hooks.sh
```

Installed the app rather than the source? The same scripts travel inside the
bundle:

```sh
"/Applications/HashNotch.app/Contents/Resources/scripts/install-claude-hooks.sh"
```

From then on the island lights up when Claude **finishes a reply** — a tick,
about three seconds, then gone — or is **waiting for your permission**, which
stays until you deal with it and says what it is asking for. Click that one in
the panel and it brings the waiting window to the front.

It uses Claude Code's own hook system. The hook is a small script that writes
only this feed file, and the installer backs up your Claude settings first.

> **Re-run the installer after updating the app.** The hook is copied into your
> home folder so you can read exactly what it does, which also means it does not
> follow app updates on its own. Re-running is safe at any time and tells you
> what it did — installed, already current, or updated from one version to the
> next.
>
> You do not have to remember. When the copy in your home folder is older than
> the one the app ships, the panel says so and offers to copy the command for
> you — it never runs it, because that edits `~/.claude/settings.json` and this
> app does not change another tool's settings because a cursor went past the
> notch. The notice compares version numbers rather than file contents, so
> editing your own copy of the hook does not produce a warning that will not go
> away.

> **Want a tool's logo instead of the symbol?** Drop a square PNG at
> `~/.hashnotch/logos/claude.png`. No logos ship with the app — those marks
> belong to the tools they represent, not to this one.

**HashCortX** and **HashCerebrum** post to the same feed and need nothing
installed.

---

## When a tool is waiting on you

An agent that needs permission stops and asks in its own window, and the notch
tells you that it has: **"Claude needs you"**, with the reason underneath, and a
line around the notch held amber until it is dealt with. Click it and the window
that is waiting comes to the front.

That is the whole of it. The notch reports; it never intercepts. The hook writes
the activities feed and returns nothing the agent acts on, so no tool call is
ever held open waiting for the notch, and a permission question is answered
exactly where it was asked.

There was once an **Allow** and **Deny** pair here, with the hook stopping the
call and waiting for a decision. It is gone. Every version of it charged a wait
to tool calls that were never in doubt — the event a hook can intercept on runs
*before* the permission decision, so nothing it is handed can say whether
anybody was going to be asked at all — and being told, then answering where the
question actually is, turned out to be what was wanted.

---

## Every other AI tool

Nothing about the notch is Claude-specific. Anything that can run a command when
it finishes can light it, and most agents can — either through a hook of their
own or, failing that, by putting a command after theirs.

Give yourself one word for it. Add this to `~/.zshrc`:

```sh
notch() { "/Applications/HashNotch.app/Contents/Resources/scripts/post-activity.sh" "$@"; }
```

Then any tool, hooks or no hooks:

```sh
codex exec "refactor the parser" ; notch --notice 3 "Codex finished" "" checkmark
aider --message "add tests"      ; notch --notice 3 "Aider finished" "" checkmark
gemini -p "review this diff"     ; notch --notice 3 "Gemini finished" "" checkmark
```

`;` rather than `&&` on purpose: a tool that fails is exactly the one you want
to be told about. To say which way it went:

```sh
my-agent "..." && notch --notice 3 "Agent finished" "" checkmark \
                || notch --notice 5 "Agent failed" "" exclamationmark.triangle
```

Something long-running can hold the notch while it works and hand it back at the
end. The two commands share an `--id`, so the second replaces the first rather
than stacking up:

```sh
notch --id train "Training" "epoch 1/20" brain 45
./train.sh
notch --id train --notice 4 "Training finished" "" brain
```

If your tool has a hook system — most agents do — point it at the same command
and it will fire without you wrapping anything. Every field it can post, and
what the app refuses, is documented in "The feed" above; the app treats it as
untrusted whoever writes it.

> Symbols are [SF Symbols](https://developer.apple.com/sf-symbols/) names, so
> anything in Apple's set works: `checkmark`, `hammer`, `bolt.fill`, `brain`,
> `terminal`, `exclamationmark.triangle`.

---

## Your AI usage

Today's token use, one glance away. The strip shows a running total; the panel
breaks it down per tool — Claude Code, HashCortX, HashCerebrum — counted the
same way [HashMeterAi](https://github.com/Hash-7777/HashMeterAi) counts them, so
the two always agree.

It reads only the local usage files those tools already write
(`~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and
HashCerebrum's usage log) — read-only, adding up numbers and nothing more. Only
what has been appended since the last count is read, so it stays cheap however
often you ask. How often is yours to set in Settings — from every ten seconds to
once every two hours, or only when you ask — and it counts on that rhythm
whether or not the panel is open, so the figure on the notch is as fresh as the
setting says.
