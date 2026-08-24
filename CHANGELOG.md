# Changelog

All notable changes to HashNotch are recorded here.

## Unreleased

### Added

- **Which programs used your data, not just how much.** Under the data-used
  figure the panel now carries a list you can open and shut: which programs used
  the most — three of them — exactly what each sent and received, and a bar under
  each one comparing it with the biggest — split into the same two colours as the
  figures beside it, so the picture and the numbers are the same fact. Shut, it
  costs a single line and still names the biggest. It says "while running", and
  means it: your Mac keeps no history of which program used what, because those
  counters live inside the running programs and go when they do. Anything that
  went past while the app was closed is in the total above but belongs to no
  program that can still be asked. The total does not have that limit. Nine gigabytes today is a number
  you can do nothing with; eight of them being one program is one you can. It
  comes from `nettop -P`, Apple's own tool and the one Activity Monitor's
  Network tab is built on: no permission, no address, no site, and nothing
  leaves your Mac. It has its own switch under **Settings → General** because it
  is a different kind of reading from the rest of that indicator — the byte
  counters know nothing about which program sent what, and this knows — and
  switching it off stops it being asked rather than hiding the answer, and
  deletes what it had recorded.

- **The notch tells you when its hook has fallen behind.** The Claude Code hook
  is copied into your home folder so you can read it before it runs, and the
  price of that is that it does not follow an app update: change what the notch
  says when a tool finishes, and every copy already installed keeps doing the old
  thing with nothing anywhere to say why. That has already happened once. The
  panel now shows a line when the copy you have is older than the one the app
  ships, and clicking it copies the command that fixes it — it does not run it,
  because that edits another tool's settings file and no click on a panel that
  opens when a cursor passes the notch should do that. It compares version
  numbers rather than file contents, so editing your own copy never produces a
  warning you cannot clear.

- **Allow or deny from the notch.** An agent that needs permission stops and
  asks in its own window, which means finding that window. It can ask here
  instead: hover the island and the panel shows what it wants to do, with Allow
  and Deny on it. Off until you name the tools you want to be asked about, one
  per line in `~/.hashnotch/ask-tools.txt`, and every way it can go wrong ends
  in the ordinary prompt — the app not running, nobody answering within twenty
  seconds, or the hook failing at all. Deny is drawn no louder than Allow: a
  pair of buttons where one is styled as the obvious answer is a pair that gets
  clicked without reading, and the reading is the point.

- **How much you have used, not just how fast it is going.** The panel now says
  how many gigabytes have gone down and up — today by default, or this month, or
  since you last reset it, whichever you pick under Settings → General. It is
  counted from the same readings the speed has always been measured from, so it
  costs one reading of your Mac's own counters a minute and asks for no
  permission and no network. Traffic through a VPN, a bridge or a virtual
  machine is counted once rather than twice, on the way past the real
  connection. And when the figures cover less than the stretch they are named
  after — the first day you have it, or a month that began before you installed
  it — the panel says from when it has been counting rather than quietly
  understating the number.

- **The notch lights up around its edge, the way an iPhone does.** A line one
  screen pixel wide traces the black pill itself, down the sides and around the
  bottom — never across the top, where there is bezel rather than screen — and
  fades out as it reaches up under it. Every battery moment has a colour: green
  going on the charger and green again when it is full, white for running on the
  battery, orange for running out. A microphone open anywhere holds it red for
  as long as it is open. And anything posted to the activity feed lights it too:
  green when a job has finished — an AI tool ending its turn, a build completing
  — and amber when something is waiting on an answer and cannot go on until it
  gets one. Work merely in progress lights nothing, because a colour that
  appears for everything announces nothing. The badge beside the words wears the
  same colour as the line, because they are one signal.
- **The line now traces the island instead of floating under it.** The strip was
  exactly as tall as the notch, so a line along its bottom edge sat behind the
  hardware for the notch's whole width — present on the shoulders, missing in
  the middle. Drawing it lower fixed the middle and spoiled the shoulders, where
  it left the black and hung over the desktop with a gap between the pill and
  its own outline. Neither is fixable while the pill ends exactly where the
  hardware does, so the strip now hangs three points lower than the notch and
  the line sits on black the whole way round. The idle shape is untouched: a
  notch with nothing to say still shows no lip at all.
- **"Claude needs you" leaves as soon as you have dealt with it.** It waits
  rather than dismissing itself, because it is asking for something — but the
  only thing that used to take it down was Claude finishing its turn, which can
  be minutes after you answered. It now goes the moment the session moves again:
  a prompt submitted, or a tool running because you granted permission. A
  finished notice is left alone to run out its few seconds. **Re-run
  `./scripts/install-claude-hooks.sh` for this** — it registers two more events.
- **A logo on the notch is drawn larger than a symbol.** A symbol's size is the
  glyph plus the tinted disc behind it; a logo has no disc, so that same room is
  all artwork. It matters more than it sounds for a mark made of fine lines,
  which has to survive being drawn about forty pixels tall — a stroke that lands
  under a pixel breaks up instead of drawing.
- **The Claude hook says which tool finished, not what kind of work it was.**
  The symbol it posts is now the one macOS itself uses for anything to do with
  an assistant. **Re-run `./scripts/install-claude-hooks.sh` to pick it up** —
  the installed copy of the hook lives in `~/.hashnotch` and does not follow app
  updates.

### Changed

- **How much you have used no longer looks like how fast you are going.** The
  total sat directly under the speed row and was drawn exactly like it — same
  label, same pair of arrows and figures, same colours, same size — so two
  readings that answer completely different questions looked like one reading
  given twice. A speed is true for an instant and moves both ways; a total only
  grows, and you look at it once a day. It is now a block rather than a row: one
  figure large enough to be the answer, a bar underneath showing how much of it
  came down and how much went up, and those two figures named quietly beneath
  that. The bar divides the total rather than filling towards anything — there
  is no allowance, no plan and no limit here, and a bar that fills would invent
  one. It is drawn a little heavier than the per-program bars under it, because
  it is the thing they are a breakdown of.

- **Every heading in the panel now has its own mark.** A small drawn picture in
  front of each one — a chip for the processor, a memory chip, a stack of
  platters for the disk, a globe for the internet, a thermometer, a stopwatch, a
  spark for the AI count — so a row can be found by its shape before it is read.
  The panel is a dense list of unrelated readings and the eye needed somewhere to
  land. They are drawn rather than borrowed from the system's symbol set, for one
  reason worth knowing: a system symbol that a given version of macOS does not
  have draws nothing at all, silently, and nothing on a newer Mac would ever
  notice the empty space it leaves on an older one. Every mark is laid out on one
  grid at one line weight, so they read as a family, and the checks measure them
  — that each stays inside its own box, that no two came out the same drawing,
  and that they are the same shape at every size.

- **The battery is drawn to the level it is actually at.** Both on the notch and
  in the panel, it is now a real battery that fills and empties, the way the one
  in your menu bar does — with the bolt while it charges, a pause while it is
  held at a ceiling for its health, yellow in Low Power Mode, and red when it is
  nearly out. Before, the strip drew the same full-battery symbol for anything
  running down, so the shape beside "4%" was a full battery, and the panel drew
  no battery at all.

- **The AI token count now counts on its own.** It was only ever counted while
  the panel was open, which quietly made "every 5 minutes" mean "every 5 minutes
  that you happen to be looking at it" — so the figure on the notch sat unchanged
  for hours and then jumped the moment you opened the panel. It now counts on the
  rhythm you choose whether or not anything is on screen, and there are more
  rhythms to choose from: every 10 or 30 seconds, every 1, 2, 5, 10, 15 or 30
  minutes, every hour or two, or only when you ask. A count with nothing new to
  read opens no file at all, which is what makes even the short settings cheap.
  A fresh install now starts at 5 minutes rather than 30, because 30 was chosen
  when the number was refreshed by the act of looking at it.

- **A tick, not stars, when an AI tool finishes.** Stars are the house mark of
  every AI product at once, so they named the category rather than the event —
  and at the size the notch draws them, two stars of different sizes have no
  balance point, so the badge never looked centred. One stroke does.

- **A request says how long it has been waiting, and presses harder the longer
  it does.** "Claude needs you" used to show the time LEFT before it gave up and
  left the screen — a countdown on a question, which measures when the app stops
  asking rather than how long the answer has been owed. It now counts up, says
  nothing for the first minute, and the line around the notch breathes a little
  faster and dims a little less as the wait goes on. That is the whole
  escalation: no growing, no second alert, no sound. And because answering now
  takes it down, it no longer has to expire while you are still thinking.
- **Any AI tool can light the notch, not just the ones named here.** The docs
  now carry the generic route — one line in your shell profile, then a `;` after
  whatever you already run. Worked examples for tools with no hook system at
  all, including telling success from failure and holding the notch through a
  long job.

- **Every panel can be dragged out of the way.** The windows the app puts up —
  the quit question, the opening window, settings, and the old-copy notice —
  have no title bar, and until now there was nothing to take hold of. Each one
  can now be moved by its heading, the way a title bar works.

### Fixed

- **Locking your Mac no longer cancels your timer.** This is the serious one.
  Every indicator is stopped when the island leaves the screen — that is the
  privacy promise, and it is the right thing for all of them but one. Stopping
  the timer threw away the countdown, so a timer set at your desk was silently
  gone when you came back: no alert, no countdown, and nothing anywhere saying
  one had ever been started. The display sleeping after ten minutes is not an
  unusual thing to happen to a twenty-five minute timer; it is the ordinary
  thing, so this was most timers. The deadline is now kept, because a countdown
  is not a reading — it is a time you typed in yourself. Everything the app
  MEASURES still stops dead on a lock, and a feature that says nothing on the
  subject still stops entirely, so nothing else can survive a lock by accident.

- **The alert arrives on time, even with the screen asleep.** It used to be
  posted at the moment the app itself noticed the countdown reach zero — and the
  app stops sampling when the display sleeps, so the one moment a timer most
  needs to be heard was a moment when nothing was running to hear it. The
  deadline is now handed to macOS when the timer starts, so the alert is the
  system's job: it lands on time whether the display is asleep, the panel is
  shut, or the app is busy. Cancelling the timer takes the alert back with it —
  before, a cancelled timer's alert had an unrepeatable name and nothing could
  ever have cancelled it.

- **A timer going off while music plays is now visible.** The strip shows one
  thing at a time and the media indicator is registered first, so at equal
  standing it kept the strip through the exact moment the timer had something to
  say. "Time's up" now takes the strip for its few seconds, with the island's
  edge lit orange, and hands it straight back. The countdown itself keeps the
  lower standing — a song you are listening to beats a number ticking down.

- **If you refuse notifications, the panel says so.** The app asked for
  permission and threw the answer away, so somebody who said no got no banner,
  no explanation, and an app that looked exactly as it had before. The timer
  says which alert you are getting and offers to open the settings page where
  that can be changed. A chime needs somebody within earshot; a banner waits.

- **The timer remembers how long you set it for.** The length lived on a view
  that is rebuilt every time the panel opens, so 45 minutes was back at 10 the
  next time you hovered the notch — and dialling it up again is nine presses.

- **One program, one row.** macOS reports a command and an application of the
  same name separately — `claude` and `Claude` — and it reports a browser's
  networking under its helper processes, whose names it then cuts short, so
  Chrome appeared as "Google Chrome H". Both showed the same program twice,
  which reads as the app having counted something twice even when both figures
  are right. They are now added together under the program's own name.

- **The battery is the shape of a battery again.** Drawing it rather than
  picking one of Apple's symbols made its proportions this app's problem, and
  the first attempt was hand-picked — seven per cent longer for its height than
  Apple's own, which read as stretched beside text that follows Apple's
  proportions everywhere else on the row. Apple's battery was measured, and the
  shape now follows from that one number and its own height, so no part of it
  can be tuned without the rest keeping step.

- **A big figure is shown in full instead of being cut short.** A month's
  download came out as "14.18…" — the row ran out of room and abbreviated the
  one thing on it that cannot be inferred from anything else. Two fixes, and
  the first is worth more than the second: every reading now carries three
  significant figures rather than a fixed number of decimals per unit, so a
  gigabyte figure no longer claims precision it does not have and no longer
  costs nine characters to say. "365 MB" and "14.2 GB" rather than "364.8 MB"
  and "14.18 GB" — the same kind of number wherever it appears. And when a row
  is still short of room, the value keeps its space and the label yields, since
  a label can be inferred from the row it sits on and a number cannot.

- **A panel row can no longer break in two, whatever is in it.** Holding the
  label to one line fixed half of this and left the other half in plain sight:
  the value beside it was unconstrained, so "held at 80% for battery health"
  wrapped instead and took the row and everything under it down with it. Values
  are held to their line now too — and that particular sentence said the number
  twice anyway, since the row it sits on already reads 80%.

- **Nothing of the app's hangs below the physical notch any more.** The live
  strip was made three points taller than the hardware so the coloured line had
  black to sit on — which solved the line and created a worse problem: a black
  lip resting on your wallpaper, visible against anything that is not black, so
  the notch stopped looking like the notch. The black is now exactly the
  hardware in every state, and the line is traced just OUTSIDE the pill's bottom
  edge instead of centred on it, which puts all of it in the couple of points of
  screen directly below the notch — the only place under a notch there is
  anything to light up.

- **The by-app list no longer judders as it opens.** Two faults, one in each
  half. The window the panel lives in was following the list's height one
  measurement at a time while it animated, so the panel was clipped by a sliver
  for the whole of the opening and its bottom edge stepped along underneath it —
  the same fault the panel's own drop had, fixed the same way it was: ask for the
  room up front, animate inside a window that is already big enough, and give the
  extra back afterwards. Measured, it is now one window resize per change instead
  of one per frame. And the list itself was sliding in from the top edge while
  the stack around it was changing height for the same reason — two motions
  describing one event — so the rows appeared to arrive from the wrong place. The
  height change is the motion now; the fade only stops the rows being drawn
  before there is room for them.

- **The battery sits beside the word "Battery", not over with the numbers.** It
  is a picture of what the row is about, which belongs to the label. On the
  right it read as one more value competing with the figures, which is the one
  thing it is not.

- **Everything on the live strip sat a point and a half too low.** The strip
  hangs slightly below the notch so the coloured outline has black to sit on,
  but its contents were being centred in the whole shape rather than in the
  notch's own band — so every badge and title sat below the centre line of the
  hardware right beside it, which is exactly the line the eye compares against.
  A sliver of bare screen was appearing above the strip for the same reason.

- **A panel row no longer becomes two rows when the number gets long.** The rows
  are a fixed width, so a long value squeezed the label beside it and the label
  wrapped: "Used today" became two lines, and every row underneath stepped down.
  The panel's shape no longer depends on how much data you have used.

- **The note under the data-used figure says what it means.** "some time not
  counted" was four words that said something was missing without saying what,
  when, or why. What it is now beside the figure is a mark you can hover, and it
  says the whole thing: that HashNotch was closed across a change of day, that
  your Mac's counters keep running but do not record *when*, and therefore that
  the real number is higher than the one shown.

- **The data-used figures cannot silently lose 4 GB at a time.** The counters
  the app was reading are 32 bits wide, so they roll over every 4.29 GB — an
  evening of video — and a counter that has rolled over looks exactly like one
  that restarted. macOS keeps the same counters at 64 bits, which is what the
  app reads now.
- **Closing the app no longer loses the day's traffic, or invents it.** The
  counters keep running while the app does not, so reopening it finds what went
  through in between. Quit at nine and reopen at five the same day and all of it
  is yours, today, and it is counted. Quit on Friday and reopen on Monday and
  there is no honest way to split it across three days, so it is not counted at
  all and the panel says a stretch of the time went uncounted rather than
  inventing the heaviest day of the month out of a weekend.
- **The panel opens in one movement, and lands rather than bounces.** Three
  things were making one opening look like three.

  The window it is drawn in was sized from whatever had been measured a moment
  earlier — which, at the instant the panel starts opening, is the collapsed
  notch. So the panel began its drop inside a window barely taller than the
  notch, and the window caught up in jumps while the panel was still moving,
  clipping it on the way and laying the whole panel out again each time.
  Measured over one opening: the window was set three times, at 84 points, then
  592, then 632. It is now sized for the panel before anything starts moving,
  and an opening sets it once.

  The panel overshot its height and rang back, which reads as wobbling rather
  than arriving. It now overshoots by a hair and settles.

  And the contents waited for the panel to land before fading in, so the box
  arrived, paused, and then filled. They now arrive with it.
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
