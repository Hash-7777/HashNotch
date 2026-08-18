# Changelog

All notable changes to HashNotch are recorded here.

## Unreleased

### Added

- **The notch lights up around its edge, the way an iPhone does.** The colour
  traces the black pill itself, and every battery moment has one: green going on
  the charger and green again when it is full, blue for running on the battery,
  orange for running out. A microphone open anywhere holds it red for as long as
  it is open.

### Changed

- **Every panel can be dragged out of the way.** The windows the app puts up —
  the quit question, the opening window, settings, and the old-copy notice —
  have no title bar, and until now there was nothing to take hold of. Each one
  can now be moved by its heading, the way a title bar works.

### Fixed

- **The notch no longer says everything twice.** Two copies of the app running
  at once does not give you two apps — it gives you two islands drawn on top of
  each other, so every alert appears twice, and there is no Dock icon or
  menu-bar item to reveal that a copy was already up. A second copy now stands
  down at once instead of starting.
- **Plugging in a second screen no longer stops the island hiding when you lock
  the Mac.** A display change rebuilds the overlay, and the lock was still
  reaching for the one that existed at launch — so after connecting a monitor
  the island stayed on screen through a lock, which is the one moment it is
  meant not to.
- **The old-copy notice has a close button, and gets out of its own way.** It
  now has a cross in the corner, and choosing to see the old app or to open
  Login Items closes the notice first — it used to stay on top of the very
  window it had just opened.
- **The app now tells you when an older copy is still installed.** If a
  `Hash D Island` from before the rename is still on the Mac, a notice explains
  what is happening and what to do about it — because from the screen there is
  nothing to see but settings that appear to have been thrown away, and a
  release note only reaches somebody who reads release notes. It says first
  that nothing has been lost, then points at the old app in Finder and opens
  Login Items. It stops appearing for good once the old app is gone, and it
  never removes anything itself.
- **Upgrading no longer looks like the app losing every setting on restart.**
  Installing HashNotch does not replace an older `Hash D Island` — the names
  differ, so both sit in Applications, and macOS records "open at login"
  against the old one by file reference rather than by name. Every restart
  quietly launched the old app: its own separate settings, so the panel came
  back with nothing you chose, and its own app identity, so the permission
  questions were asked again. Nothing was ever lost. Building from source now
  clears an app bundle left behind by a previous name instead of leaving it
  sitting there launchable, and the README says plainly to bin the old app and
  clear its Login Items entry.

## 1.2.0 — the name comes back, and the quit button works

### Changed

- **The app is called HashNotch again.** Everything carries the name: the app in
  your Applications folder, the words in its windows, the settings it saves, and
  the folder other tools post activities into. Nothing you have set up is lost —
  your settings are carried across the first time you open it, and the notch
  goes on reading the old activities folder for as long as anything is still
  writing there, so alerts from Claude Code and other tools keep arriving before
  you have re-run anything.
- **Re-run the Claude Code installer when you get a chance.** The hook folder
  moved with the name, and re-running `install-claude-hooks.sh` points Claude
  Code at the new one and brings any logos you added across with it. Everything
  keeps working until you do.
- **The disk image is named without a space in it.** GitHub turns a space in a
  download's name into a dot, which made every instruction naming that file
  wrong at the one moment somebody reads it.

### Fixed

- **The power button in the panel now actually quits.** It looked broken in
  three ways at once, and all three are gone. The panel did not close, because
  the button set it closed without telling hover to stand down — so the pointer
  still resting on the panel put it straight back up. The question then went up
  as a system alert, which stops the whole app dead while it waits, freezing the
  panel half shut. And because the app never takes focus, that alert could open
  behind whatever you were working in, leaving a question you could not see in
  front of an app that looked hung. The confirmation is now an ordinary window
  of the app's own: it appears above the island, on whatever desktop you are on,
  with the island still running behind it. Escape backs out, Return quits.
- **A finished AI tool shows only its name.** "HashCortX finished" was arriving
  with the model that answered trailing it in small grey text. The work is over
  by the time you read it, so that second line offered nothing to act on while
  crowding the part you were looking for. It now reads just "HashCortX
  finished", for any tool that posts one. A tool that is *waiting* on you still
  shows its reason, because there the second line is the whole point.

## 1.1.0 — the panel behaves

Everything here is about the panel doing what you meant, and settings being
easier to read and easier to undo.

### Fixed

- **One click now puts the panel and settings away together.** Clicking away
  used to close the panel and leave the settings window sitting there, needing a
  second click — and clicking *inside* settings dismissed the panel behind it.
  All of it came from one mistake: the overlay was handed nothing where the
  settings window should have been, so it could not see that window's position,
  could not tell that a click had landed in it, and could not close it. It now
  receives the window directly, and none of those three questions can be
  answered wrongly again.
- **The panel stays open while settings is open.** Whether it is held open is
  now decided by whether the settings window is actually on screen, rather than
  by a flag that something had to remember to set.
- **The notch follows what you turned to last.** A playing Spotify claimed it
  unconditionally, so starting something on the web while Spotify was still
  going left the notch showing the track you had stopped listening to until
  Spotify was stopped outright. Both Spotify and Music now claim it only when
  the system either names their track or names nothing at all.
- **A Mac with no battery no longer shows a battery.** On an iMac, Mac mini,
  Mac Studio or Mac Pro every part of that indicator is meaningless — no level,
  no time remaining, no adapter — and it drew anyway, dimmed, which reads as
  broken rather than as not applicable. It now stands down entirely, the same
  way AirPods does when nothing is connected. A laptop is unaffected, including
  in the moment before the first reading lands.
- **The opening window now leaves the screen before macOS asks anything.**
  Accepting starts the indicators, and starting them is what makes macOS raise
  its own prompt for the Downloads folder — so that prompt used to appear on top
  of the window that had just asked for permission itself, two consent dialogs
  stacked with the second seeming to answer the first. The window goes first
  now, then anything it triggered.
- **Reaching the top of the screen no longer closes the panel.** Hovering the
  notch opened it, and then pushing the cursor up into the bezel — still over
  the notch — shut it again. The hover area ended exactly at the screen's top
  edge, and an area does not include its own far edge, so the topmost row of
  points over the notch counted as being away from it. The area now reaches a
  little past that edge, where there is no screen for the cursor to be in. On a
  display with no notch it does not, because the menu bar's own icons are there.

### Added

- **A way to say no.** The opening window now offers *Refuse and quit* beside
  *Start*. Refusing closes the app and removes its settings file, so a Mac that
  declined is left as it was found; opening it again asks again. Escape does the
  same thing. A window that asks permission and offers one button is not asking.
- **Reset appearance**, on the Appearance page: puts the colour, fill, motion,
  rounding and separators back the way they arrived, and leaves every other page
  alone.
- **Reset all settings**, on the General page: puts the whole configuration back
  — indicators and their order, the look, alerts, position corrections, battery
  saver, both opt-ins, and open at login. Your consent to read is kept, so
  nothing stops working and nothing has to be answered twice.
- Neither reset is one click away. The button is replaced in place by a cancel
  and a confirm, so a misplaced click cannot cost you an arrangement you spent
  time on.
- **A switch for each service's covers**, under General → Cover art: Spotify and
  YouTube, separately. Each is a request to a different company, so allowing the
  one you use should not cost you requests to another you do not. Switching one
  off is enforced by the downloader itself — its hosts stop being trusted —
  rather than merely hiding the picture. With both off the app makes no network
  requests at all.
- Covers for other web players are still not shown, and that is deliberate.
  Anghami was built and withdrawn before release: its covers are reachable, but
  the identifier they hang on does not keep step with the track, so the picture
  was frequently the previous song's. A blank tile is honest; a confident wrong
  answer about what you are listening to is not.

### Changed

- **The permission switches moved from Alerts to General**, under a heading of
  their own. An alert setting is about how something looks; these are about what
  the app is allowed to do.
- **Turning on browser control clears the screen first.** Both of the app's
  windows sit above the ordinary level, so the Accessibility dialog opened
  behind them — the switch was flipped, nothing appeared to happen, and the
  thing waiting for an answer was underneath the window it was asked from.
- **The scrolling title no longer looks smudged at its first letter.** The fade
  that softens a glyph sliding out of view was applied whether or not anything
  was moving, so the first character of every title sat under a permanent wash
  of transparency. It now appears only once the title actually starts to move.
- **The title sits closer to the notch.** It stood 18 points clear while the
  artwork on the other side hugged at 6, so the two halves of the strip looked
  unequal and read as two things rather than one wrapped around the notch.
- **The opening window has one button.** There used to be a quieter "Choose what
  runs" beside it, which accepted just the same and then opened settings. Two
  buttons where one is the same answer wearing a different word read as a
  question, and that window is not asking one — it states what will be read and
  waits to be acknowledged. Everything is switchable the moment the app is
  running, and switching one off stops it reading, so nothing is lost by
  deciding afterwards.
- **Settings pages moved from a column down the left to a strip across the top.**
  The column spent about a third of the window's width showing six words that
  never change. The same six pages now cost a little height once, and every page
  gets the window's full width — which is the crowding that showed on the busier
  pages.

### Verified

- 530 automated checks, up from 493. The new ones cover both resets, what each
  leaves untouched, the two ways a reset could have failed silently, the
  top-of-screen hover fix — including one that fails if that fix is ever
  removed — and that a Mac still being read never has its battery indicator
  hidden by mistake.
- Every line of this release compiles against the package's macOS 12 deployment
  target, so nothing added here is unavailable on Monterey.

## 1.0.0 — first release

The notch becomes a living surface: quiet when nothing is happening, alive the
moment something is.

### Around the notch

- **At rest** the island matches the physical notch exactly, so the app is
  invisible until it has something to say.
- **A live strip** appears beside the notch — no hover needed — whenever
  something is happening: music playing, a timer counting down, a download
  landing, an activity running. A track keeps its place while paused, so the
  artwork and the resume button stay where you left them.
- **Hover, or swipe down with two fingers,** to drop the full panel below the
  menu bar. Because it opens below the menu bar, it never covers your menus or
  status icons.
- **The panel's own controls sit beside the notch** — quit on its left, settings
  on its right — in the band of panel the hardware leaves showing. They are
  placed by the layout rather than floated over the first row, so no order you
  put the indicators in can collide with them.

### What it shows

- **Now Playing** — works with anything that plays: Spotify, Apple Music, TV,
  Podcasts, Anghami, VLC, a video in your browser, or an app nobody has written
  support for. macOS itself is asked what is playing, so the title, artist and
  position appear for all of it with no per-app support written for any of them.
  Album art comes from Spotify and Apple Music, and a video's thumbnail from
  your browser; anything else shows a placeholder tile. A scrolling title, audio
  bars, a progress bar you can **drag to move through the track**,
  play/pause/skip, and a system volume slider.
- **Swipe sideways across the open panel** to change track — left for the next,
  right for the previous, and only while something is actually playing.
- **Microphone** — the moment any app opens your microphone, a live dot and a
  running timer appear beside the notch with that app's own icon: FaceTime,
  Zoom, Teams, a browser call, a voice memo. macOS is asked one yes-or-no
  question — does this app have an input stream open — and the app **never
  listens, records or transcribes**. It holds no microphone permission of its
  own, and could not use one. On macOS 14.4 and later it can name the app;
  below that macOS offers only a device-wide answer, so the dot appears without
  a name attached.
- **Internet speed** — live upload and download.
- **Battery** — level, time remaining, and time to charge, with the adapter's
  wattage and whether that is a slow or fast charge. A Mac limited to 80%
  counts down to that level rather than to a full battery it will never reach.
  Charging is told apart from being *held* there. A heads-up when you plug in,
  unplug, reach full, or drop through 20% and 10%, and Low Power Mode in yellow
  with one click through to the setting that owns it.
- **AirPods** — charge remaining in each earbud and the case.
- **Temperatures** — real Apple Silicon on-die sensors, grouped into
  processor, graphics, drive, battery, and system.
- **AI token usage** — today's totals per tool, counted exactly the way
  HashMeterAi counts them. Only what your tools have written since the last
  count is read, so it stays cheap however often you ask for it; how often it
  counts is yours to set, from every minute down to only when you ask. The last
  count is remembered, so the panel opens on a number rather than on a zero it
  has not earned, with a line saying how old it is.
- **Timer** — any length you choose, counting
  down at the notch, with a chime and a notification at zero.
- **Processor load** — how busy the CPU is, as a number, a full-width graph of
  the last half-minute with a floor and ceiling to read it against, or both.
- **Memory** — how much of the Mac's memory is in use, the same figure Activity
  Monitor shows, with a matching graph. On Apple Silicon the processor and the
  graphics share one pool, so this is the whole machine.
- **Storage** — how full the startup disk is and how much room is left, with a
  bar underneath. The free figure is the one `df`, `diskutil` and Finder all
  report, so it can be checked against any of them.
- **Downloads** — a short notice when one finishes.
- **Live activities** — a local feed any app, script, or Shortcut can post to,
  with a built-in integration for Claude Code, HashCortX, and HashCerebrum.

### Built for the machine it runs on

- Native Swift (SwiftUI + AppKit), tuned for 120Hz ProMotion.
- Runs on **macOS 12 Monterey through macOS 26 Tahoe**, and asks each one for
  what it can comfortably give: the newest systems get the full treatment, and
  older ones get the same design with less to composite and a little longer to
  animate. Every version runs every feature, with one exception stated plainly
  where it appears — Open at Login needs macOS 13, and says so.
- Sampling stops entirely while the screen is asleep; timers are coalesced and
  monitors publish only when a displayed value actually changes.
- With the panel shut it costs very little: **0.13–0.19% of one core, and about
  two idle wake-ups a minute**, measured over two- and four-minute windows
  against the packaged app sitting idle with nothing live on the strip. It is
  small rather than nothing, and it rises while something is actually happening
  — a feed being written to drove it to a few percent. Every reading that only
  appears inside the panel is taken only while the panel is open, anything slow
  — the sensors, the AirPods report, the token count — runs off the thread that
  draws it, and a feature switched off is never started at all.
- Every capability is a self-contained module — adding or removing one touches
  a single manifest line and never the core.

### Privacy

- No accounts, no analytics, no telemetry, no servers.
- The app writes no files; its only persistent state is its own settings, which
  now also hold the last token totals so the panel can open on a number.
- Switching an indicator off stops it reading, not just showing — a feature
  that is off is never started at all.
- **One kind of network request, and only that one:** fetching a cover. HTTPS
  only, restricted to Spotify's and YouTube's image hosts, size-capped, and
  refused if a redirect would leave those hosts. It is fetched through an
  ephemeral session, so no artwork is written to disk. Nothing else in the app
  touches the network, and nothing about you is ever sent anywhere.
- Reading what is playing sends Apple Events, as the table in
  [SECURITY.md](SECURITY.md) sets out. Spotify and Music are asked for the
  track and its position; your browser is asked for the playing tab's address
  only when a web video needs a thumbnail, once per video rather than once per
  poll, and the tab list never leaves the helper subprocess. Deny any of it and
  everything else keeps working.
- **Nothing at all while your Mac is locked.** The island leaves the screen the
  moment you lock it and every indicator stops with it — not dimmed, not
  covered, gone, and reading nothing. What the notch shows is a summary of your
  afternoon, and a locked Mac is exactly when somebody who is not you might be
  standing in front of it.
- The activity feed is treated as untrusted throughout, including the app a row
  may name: clicking one can only ever reach a real `.app` bundle installed
  where macOS keeps applications, with symlinks followed before the path is
  judged. A bundle dropped anywhere else is refused, so nothing that can write
  the feed can dress a stray app up as the window you were working in.
- Everything it reads, every permission it can ask for, and both private Apple
  APIs it uses are listed in [SECURITY.md](SECURITY.md).

### Known limitations

- HashNotch is measured to match a physical notch exactly. On a display
  without one — an external monitor, an iMac, an older Air — it is drawn against
  the top bezel and made exactly as tall as your menu bar, filling the band
  macOS never uses between the app menus and the status icons. Either way you
  can nudge its position and size per display in **Settings → Position**.
- Built for Apple Silicon (M1 and later). The temperature readout in particular
  is the real on-die sensors, which are an Apple Silicon interface.
- Because it reads system-wide Now Playing and the real temperature sensors, it
  uses Apple APIs the Mac App Store does not allow, so it is distributed
  directly and macOS asks you to confirm the first launch. See
  [Install](README.md#-install).
- The app is signed ad-hoc rather than with a Developer ID, and is not
  notarized, which is why that first launch takes the extra step.

### Licence

Released under the **[GNU General Public License v3](LICENSE)**. Free to use,
read, change and share; anything you distribute built on it stays free too.
