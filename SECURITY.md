# Security & Privacy

HashNotch is designed so you can verify every claim below by reading the
source. This page says exactly what the app reads, what it never does, and why.

## Everything stays on your Mac

No accounts. No analytics. No telemetry. No servers. HashNotch never uploads
anything, anywhere.

There is exactly **one** kind of network request the app can ever make:
fetching the picture for what's playing — album art from Spotify's own image
servers, or a web video's thumbnail from YouTube's thumbnail server. Those
requests are HTTPS-only, restricted to exactly those hosts (`scdn.co`,
`spotifycdn.com`, `ytimg.com`), and capped at 5 MB — any other URL, and any
redirect that would leave those hosts, is refused outright (see `ArtworkPolicy`
in `Sources/HashNotchKit/App/ArtworkPolicy.swift`, covered by the automated
checks).

Each service is a **separate switch**, under Settings → General → Cover art.
They are separate because each is a request to a different company, and rolling
them into one would mean allowing the service you use costs you requests to one
you do not. Switching one off is enforced by the downloader itself: its hosts
stop being trusted, so the request is refused rather than merely hidden. With
both off, the app makes no network requests at all.

**Why no other service is listed.** Covers for players other than these two are
not reachable honestly. macOS publishes a track's title, artist and album, and
it names the cover — type, size, an identifier — but withholds the image itself
from any app without Apple's entitlement, which a signed application does not
have. There is no artwork URL anywhere in what it offers. Anghami was tried,
because its identifier is one its own image server answers to; it was withdrawn
because that identifier does not keep step with the track, going stale across a
change and sometimes missing entirely, so the cover shown was frequently the
previous song's. A blank tile is honest. A confident wrong answer about what you
are listening to is not, and no amount of coverage is worth being wrong in the
place people look first.

The fetch uses an ephemeral session, so no artwork is ever written to disk.
Nothing else in the app touches the network, and nothing about you is ever sent
anywhere.

## What it writes

Almost nothing. The app itself writes **no files at all** — its only persistent
state is its own settings, stored where every Mac app stores them
(`~/Library/Preferences/com.hashnotch.app.plist`). Alongside your choices,
that holds two small pieces of remembered state. The last AI token totals and
the day they belong to, so the panel opens on a number rather than on a zero it
has not earned — four integers and a date, and a set from any day but today is
discarded rather than shown. And, for the data-used figures, how many bytes went
through on each of the last sixty-two days, together with where this Mac's own
network interfaces had got to when they were last read, which is what makes it
possible to tell a day's traffic from a counter that has been running since the
machine was switched on. That record is bytes and dates and the names of your
own interfaces — never an address, a site, or anything about where any of it
went, none of which the app can see in the first place.

If the panel is naming the programs that used the most, that record sits in the
same place under `hashnotch.network.apps.v1`: for each of the last sixty-two
days, up to a dozen program names and how many bytes each of them sent and
received. Program names and byte counts, nothing else — not what any of them
connected to, which this app cannot see. Switching the setting off deletes it
rather than leaving it in place unread.

If you switch on answering permission questions from the notch (see
[docs/ACTIVITIES.md](docs/ACTIVITIES.md)), your answer to one is left in the same
place under `hashnotch.answers.v1`, where the tool that asked collects it. It is
a letterbox rather than a record: only the last handful are kept, they say
nothing about what was asked, and the app keeps no log of what you have allowed. It never writes to the files it reads, and artwork
is fetched through an ephemeral session so not even an image cache lands on disk.

The one folder that carries HashNotch's name, `~/.hashnotch`, is written by
*you* — by the optional helper scripts in `scripts/`, or by anything else you
choose to post activities with. The app only ever reads it.

## Removing it

Correspondingly short, and this is every trace:

1. Settings → turn **Open at Login** off, then **Quit HashNotch**.
2. Drag the app from Applications to the Trash.
3. Delete `~/.hashnotch`.
4. `defaults delete com.hashnotch.app`

If you ran the Claude hook installer, also remove the entries mentioning
`claude-code-hook.sh` from `~/.claude/settings.json` — a backup sits next to it.

**If you ever ran this app under its former name, Hash D Island,** two more
things of its are on the disk and neither is removed by the steps above:
`~/.hashdisland`, and its settings, which come out with
`defaults delete com.hashdisland.app`. This app reads both — the folder as a
fallback for the activity feed, the settings as the carry-over that stops an
existing user being asked everything again — so they are worth naming here
rather than leaving as a residue of a rename.

No launch agents, no caches, no receipts. That is the complete list.

## Nothing at all while your Mac is locked

The island leaves the screen the moment the Mac locks, and every indicator stops
with it. Not dimmed, not covered — gone, and reading nothing.

This is deliberate rather than incidental. What the notch shows is a summary of
your afternoon: what you are listening to, which app has your microphone open
and for how long, how much you have spent on AI today, how hard the machine is
working. A locked Mac is exactly the moment somebody who is not you may be
standing in front of it.

macOS already puts the login window above ordinary windows, so the island would
be *covered* anyway. Covered is not the same as absent, and this is the one
claim where the difference is worth code: the overlay is taken off screen and
the features are stopped, so there is nothing to be covered and nothing being
read. Everything returns when you unlock.

The same applies when the display sleeps, where it is a battery decision as much
as a privacy one.

## What it reads, and why

| What | How | Why |
| --- | --- | --- |
| Network speed and data used | Kernel per-interface byte counters (`sysctl(NET_RT_IFLIST2)` → `if_data64`) | The up/down readout, and the running total of how much has gone through. It counts bytes only — it can never see what you send or receive. The totals are kept per day in your preferences (see "What it writes"); tunnels, bridges and loopback are left out of them so the same traffic is not counted twice. Read once a minute with the panel shut, since a total that only counted the moments you were looking at it would not be one. macOS reports these counters rounded down to the nearest kilobyte to any app it has not signed itself, so a single reading can be under by up to a kilobyte; the rounding cancels between one reading and the next rather than building up, because what is counted is the distance between two readings. The obvious call for this, `getifaddrs`, is deliberately not used: it hands back 32-bit counters that wrap every 4.29 GB, and a wrap is indistinguishable from an interface restarting, so a day's total would silently lose up to that much. |
| **Which programs used the network** | A short `/usr/bin/nettop -P` subprocess — Apple's own tool, the one Activity Monitor's Network tab is built on | The two rows under the data-used figure, naming the programs that used the most and what each of them used. **This is the one reading in the network indicator that knows anything about your programs**, which is why it has its own switch under Settings → General and why switching it off stops the subprocess running rather than hiding its answer. `-P` asks for totals per process: no address, no port and no remote host is requested or returned, and without root `nettop` reports only processes running as you. What it gives back is a byte counter per process, which is turned into a day-by-day record exactly the way the totals are, kept in your preferences beside them, and never leaves this Mac. Physical links only, so a VPN's traffic is not counted twice. Read once a minute, out of process so it can never wedge the app, and killed if it takes more than 5 seconds. A long program name arrives truncated by macOS and is shown truncated — nothing is invented to complete it. |
| Battery | IOKit power-source info, the connected adapter's own rating (`IOPSCopyExternalPowerAdapterDetails`), and the system's Low Power Mode flag (`ProcessInfo`) | Level, whether it is charging / held / full, time remaining or time to full, how many watts the adapter supplies, and whether Low Power Mode is on. All read-only. macOS offers no public way to *switch* Low Power Mode, so the panel's row opens System Settings at the Battery pane — unless you turn on "Switch Low Power Mode from the panel", which runs the one command that can and therefore asks macOS for an administrator password every time. |
| Temperatures | Apple Silicon on-die sensors via the IOKit HID event system | The temperature readout. Read-only. |
| AirPods battery | A short `/usr/sbin/system_profiler SPBluetoothDataType` subprocess — the same public report the System Information app shows you | The AirPods readout. That report lists every paired Bluetooth device; the app reads the battery percentages under the AirPods entry and discards the rest. Read-only, runs out of process so it can never wedge the app, and is killed if it takes more than 5 seconds. |
| Now Playing | A short `/usr/bin/osascript` subprocess asks macOS and Spotify/Music for the current track, its position and the instant that position was true; for a web video it reads your browser's open tab addresses and titles to find the one whose title matches what's playing, and derives that video's thumbnail (the tab list stays inside the subprocess — only the matching thumbnail URL comes back). Browsers are asked **once per video**, not once per poll. The app also tries the same interface in process first, which is faster and would carry artwork for every app — but macOS gates that behind an entitlement a signed application does not have, so on a shipped build it returns nothing and the subprocess answers instead. A CoreAudio started/stopped signal and the players' own public play-state broadcasts wake the reader immediately | The media display, for any app that publishes a track. The play/pause/skip buttons send fixed commands: to Spotify/Music via their scripting, to anything else via the system's media channel, and to a browser by pressing the keyboard's media keys if you have allowed that. Dragging the progress bar asks the system to move the playhead. Runs out of process so it can never crash the app, and is killed if it takes more than 10 seconds. |
| **Microphone in use** | CoreAudio is asked one question per audio process: *is this process running an input stream?* The answer is a **boolean**. No audio is opened, no samples are read, and **the app holds no microphone permission** — reading this flag is not using the microphone, the way seeing a door is shut is not going through it | The live dot and the call timer. It shows that an app has your microphone open, which app it is, and for how long. It cannot know who you are speaking to, whether anyone is speaking, or what is said — **nothing is listened to, recorded or transcribed, ever**, and there is nothing here that could be extended to do so: the API returns a flag and a process id. The process id becomes a name and an icon through the list of running applications. Only real apps count, because macOS's own dictation service holds an input stream open permanently — and that filter is for *being an app*, not a list of meeting apps by name, so FaceTime, Zoom, Teams, Meet in a browser, a voice memo or a game all work without any of them being named anywhere. Dictation itself is not detectable this way and is deliberately not guessed at. Below macOS 14.4 the per-process list does not exist; the app then falls back to a single device-wide question — is *anything* using the default input — so the dot still appears but names nothing, which is the honest answer when nothing can be attributed. |
| System volume | CoreAudio, the public system-audio API | The panel's volume slider — read with each media poll, written only while you drag it. The same control your volume keys drive; no subprocess, no permission. |
| AI token usage | Local usage files: `~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and HashCerebrum's `usage.jsonl` | The tokens-today readout. Read-only; it adds up numbers and nothing more. Each file's read position is remembered within a run, so a count reads only what your tools have appended since the last one rather than re-reading the day's transcripts every time. How often it counts is yours to set in Settings, from every ten seconds down to only when you ask, and it counts on that rhythm whether or not the panel is open — a running total for today that only moved while somebody was looking at it would be a record of when the panel was open rather than a total. The last figures are kept in the app's own preferences so the panel can show a number immediately. |
| Processor load | The kernel's own tick counters (`host_statistics`) | The CPU readout. It reads how many ticks the machine spent busy versus idle — a total, with no notion of which programs were responsible. No permission, no subprocess. |
| Storage | The startup disk's capacity, from the public file-system API | The "74% full" readout and the bar under it. It asks how big the disk is and how much is free right now — the same figure `df` and `diskutil` report, so you can check it against either. It never lists, opens or looks inside a single file, and needs no permission. A breakdown by category is deliberately not attempted: every honest way to produce one is either a full walk of your disk or a permission prompt for folders this app has no other reason to open, so the row offers a link to macOS's own Storage settings instead. |
| Memory | The kernel's own virtual-memory counters (`host_statistics64`) and `hw.memsize` | The memory readout. It reads how many pages the machine has in use in total, with no notion of which programs are responsible. No permission, no subprocess. |
| Downloads | Lists the file names in your `~/Downloads` folder | The "download finished" notice. It reads names and dates only — it never opens, moves, or uploads a file — and shows the name of a file that just completed. |
| Live activities | `~/.hashnotch/activities.json`, written by your own scripts or Shortcuts | The activity strip. Treated as untrusted input: capped at 256 KB and 8 activities, text length-limited, progress clamped, a logo refused unless it is a readable image under 4 MB. An activity may also name an app to bring forward. That happens only when **you click the row**, and the app named is held to three rules: it must be a real `.app` bundle, it must live where macOS keeps applications (`/Applications`, `/System/Applications`, `/System/Library/CoreServices`, Apple's sealed cryptex volume that `/Applications/Safari.app` really points into, or `~/Applications`), and any symlink is followed before it is judged, so a link cannot stand in an allowed folder while pointing outside one. Clicking brings it forward if it is open and starts it if it is not — which is why a bundle dropped anywhere else is refused outright: this feed is writable by anything running as you, and without that rule a stray `/tmp/Update.app` could wear the words "your build finished". It can never run a loose executable, pass it an argument, or open a document. The optional Claude Code integration is a hook script YOU install (`scripts/install-claude-hooks.sh`, which backs up your Claude settings first); the hook writes only this feed file, and reads only which app it is running inside so that clicking can take you back to it. |
| Media keys | `CGEvent`, only with Accessibility granted and only when you have switched it on | So the panel's play, pause and skip buttons can drive a video in a browser. It SENDS three specific keys — play/pause, next, previous — and reads nothing at all. It never captures a keystroke, and with the setting off no key is ever sent. |
| Mouse position, scrolling, and mouse-button presses | Global observe-only monitors | So the island opens when you hover the notch, a two-finger swipe on the notch opens/closes the panel, and a click anywhere else puts the panel away. Scroll events are only ever acted on while the cursor is on the island. The button monitors see only that a press happened and where the pointer was — never what was clicked, and never in any other app's content — and they observe: the click still reaches whatever it was aimed at. **It never captures keystrokes**, and mouse monitors need no permission (only keyboard ones do). The overlay is fully click-through except while the panel is open — only then does the panel itself receive clicks (for the media buttons), and it turns click-through again the moment it closes. |

## Permissions it may ask for

- **Automation (control Spotify / Music)** — no longer asked in order to *read*
  anything: what is playing now comes from macOS itself. It is asked the first
  time you press play, pause or skip on a track owned by Spotify or Music,
  because once either is paused it releases the system's media session and only
  its own scripting can start it again. Deny it and everything except those two
  buttons for those two apps keeps working.
- **Automation (control your browser)** — on a current macOS, not asked at all:
  a web video's picture now comes from the system with everything else. It
  remains only on the fallback path described in the table, asked only if a web
  video is playing and nothing else already provided artwork. HashNotch then reads your open
  browser tabs' addresses and titles to find the one whose title matches what's
  playing, and derives only that video's thumbnail. This happens once per
  video, not continuously: the result is remembered — including "no thumbnail
  for this one" — so a track that has no web thumbnail does not cause a repeat
  scan. The tab list never leaves the helper subprocess: only the single
  matching thumbnail URL is returned to the app, and only its image (from
  YouTube's thumbnail host) is fetched. Deny this and Now Playing simply shows
  a placeholder tile instead.
- **Your Downloads folder** — macOS protects it, so the first time the download
  notice looks there, macOS asks. Deny it and every other feature keeps
  working; you simply get no "download finished" notice.
- **Notifications** — asked the first time you start the timer, so it can post
  a banner when the timer ends. Deny it and the timer still chimes and shows
  "Time's up" in the notch.

- **Accessibility** — asked **only if you turn on "Control video in your
  browser"**, and never otherwise. It is off by default. macOS gates pressing
  the keyboard's media keys behind this permission, and pressing them is the
  only way to reach a video playing in a browser: the system's media channel
  accepts play and pause commands for one and does nothing with them (measured
  — pause returns success, the video keeps playing). With this off, the media
  buttons still work for Spotify and Apple Music, which have scripting
  interfaces of their own.

That is the complete list. HashNotch never asks for Input Monitoring,
Screen Recording, or Full Disk Access, and asks for Accessibility only if you
switch on the one setting above.

## Nothing runs until you have been asked

The first time you open HashNotch, it has read nothing. Before a single
indicator starts, a window lists what each one reads and what it will never do,
and nothing begins until you accept it.

This is stricter than it sounds, because it is not a notice with an OK button.
Until the answer is yes, `FeatureRegistry.syncRunning` stops every feature
rather than starting any, so the state before you accept is the same state as
switching everything off — no file is opened, no subprocess runs, and none of
the macOS permission prompts below can be triggered.

There are **two** answers. *Refuse and quit* closes the app and removes its
preferences file on the way out, so a Mac that declined is left exactly as it
was found — no settings, no state, nothing remembering that it was asked.
Opening the app again asks again. A consent window with only one button is not
consent; it is a notice with a delay.

Once it is running, every indicator can be switched off, and switching one off
stops it reading rather than merely hiding it.

It exists because of a fair criticism. Every indicator honoured its switch and
none of them ever sent anything anywhere — but they all shipped **on**, and the
app began reading at launch, so the first opportunity to decline arrived after
the reading had already happened. Being able to switch something off afterwards
is not the same as having been asked.

An install that predates this is not asked again: it chose its indicators long
ago, and interrupting it to ask a question it has effectively answered would be
noise. Only a genuinely new install sees the window.

The behaviour is covered by the automated checks, including that a feature
switched **on** still does not start while consent is outstanding.

## Off means off

Every row in the table above belongs to a feature you can switch off in
**Settings → Indicators**, and switching one off **stops the work, not just the
display**. A feature that is off is never started: it opens no files, runs no
subprocess, and can trigger none of the permission prompts above. Turn
Downloads off and the folder is never listed; turn Now Playing off and your
media apps and browsers are never asked anything.

The same holds while your screen is asleep — all sampling stops until it wakes
— and a feature you switched off does not quietly come back on wake. This is
covered by the automated checks (`FeatureRegistry.syncRunning`).

## Private APIs, stated openly

Two features use non-public Apple APIs, both read-only:

- **MediaRemote** — the only way to read system-wide Now Playing. Reached
  through an `osascript` subprocess, because Apple gates the direct call behind
  an entitlement that a signed application does not carry: called from inside
  this app it returns nothing at all. `osascript` is Apple's own binary and is
  not held to that check.
- **IOHIDEventSystemClient** — the only way to read the real Apple Silicon
  temperature sensors.

Everything else, including the microphone readout, uses documented public
interfaces. `kAudioHardwarePropertyProcessObjectList` is declared in Apple's
own `AudioHardware.h`.

If Apple changes either, those readouts degrade to a placeholder and the rest
of the app keeps working. Because of these APIs, HashNotch is distributed
directly rather than through the Mac App Store.

## Verify it yourself

The whole app builds from source with the Command Line Tools alone:

```sh
swift build
swift run HashNotchChecks   # the automated checks, including the policies above
```

All commits on this repository are SSH-signed.

## Reporting a vulnerability

If you find a security issue, please open a private security advisory on this
repository's GitHub page (Security → Advisories → Report a vulnerability), or
open an issue if it is not sensitive. Reports are welcome and taken seriously.
