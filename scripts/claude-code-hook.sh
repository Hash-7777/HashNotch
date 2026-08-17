#!/usr/bin/env bash
#
# Posts a HashNotch live activity when Claude Code finishes a reply or is
# waiting for your permission. Wired into ~/.claude/settings.json as a Stop +
# Notification hook by scripts/install-claude-hooks.sh. Reads the hook payload
# Claude Code sends on stdin (JSON) and writes ONLY the local activities feed
# (~/.hashnotch/activities.json) — nothing else, nowhere else.
#
#   claude-code-hook.sh stop           # "Claude finished"
#   claude-code-hook.sh notification   # "Claude needs you" (+ the reason)
#
set -euo pipefail

# Bumped whenever this script's OUTPUT changes. The installer copies this file
# into ~/.hashnotch, so an installed hook keeps running whatever version was
# current the day it was installed — it does not follow app updates. Stamping it
# is what lets the installer say "updated v1 to v2" rather than replacing the
# file in silence, which is how a fixed alert can go on looking broken for
# months. Read with: grep HOOK_VERSION= ~/.hashnotch/claude-code-hook.sh
HOOK_VERSION=5

EVENT="${1:-stop}"
# A logo to show instead of the symbol, if one has been placed here. Claude's
# own mark is not shipped with this app — drop a PNG at this path and the notch
# uses it; without it the checkmark symbol is shown exactly as before.
LOGO="$HOME/.hashnotch/logos/claude.png"
PAYLOAD="$(cat 2>/dev/null || true)"
FEED="$HOME/.hashnotch/activities.json"
mkdir -p "$(dirname "$FEED")"

# Which app is Claude running inside — the terminal, the editor, or Claude's own
# desktop app. Written into the activity so that clicking "Claude needs you" in
# the panel brings that window forward instead of leaving you to hunt for it.
#
# Found by walking up the process tree to the nearest ancestor living inside an
# .app bundle, rather than by reading TERM_PROGRAM: that variable is unset
# entirely under the desktop app, and wrong whenever a shell has been re-exec'd.
# Walking up costs a handful of `ps` calls once per alert.
owning_app() {
  local pid=$PPID ppid comm
  local depth=0
  while [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
    read -r ppid comm <<< "$(ps -o ppid=,comm= -p "$pid" 2>/dev/null || true)"
    [ -z "${ppid:-}" ] && return 0
    case "$comm" in
      *.app/Contents/MacOS/*)
        # Keep everything up to and including the .app itself.
        printf '%s' "${comm%%.app/Contents/MacOS/*}.app"
        return 0
        ;;
    esac
    pid="$ppid"
    depth=$((depth + 1))
  done
}
APP="$(owning_app || true)"

# All JSON handling in JavaScript-for-Automation (always present on macOS —
# no jq or python needed). Arguments pass as argv, so payload quoting is safe.
osascript -l JavaScript - "$FEED" "$EVENT" "$PAYLOAD" "$LOGO" "$APP" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  const event = argv[1];
  const logoPath = argv[3] || '';
  const appPath = argv[4] || '';
  let payload = {};
  try { payload = JSON.parse(argv[2] || '{}'); } catch (e) {}

  // "Finished" has already happened, so it is a notice: it shows for a moment
  // and leaves, with no timer counting down beside it. "Needs you" is a
  // standing request — it waits, because dismissing it after a few seconds
  // would hide the very thing it is asking you to deal with.
  let icon, title, subtitle, dismissAfter = null, waitSeconds = null;
  if (event === 'notification') {
    icon = 'hand.raised.fill';
    title = 'Claude needs you';
    subtitle = String(payload.message || '').slice(0, 120) || null;
    waitSeconds = 180;
  } else {
    // A tick is what every notification on the machine uses, which makes it
    // the one symbol that says nothing about WHAT finished. Angle brackets are
    // the universal mark for code, and on a black notch beside the word
    // "Claude" they read instantly as a coding tool having finished its turn.
    icon = 'chevron.left.forwardslash.chevron.right';
    title = 'Claude finished';
    // No subtitle. This carried the working folder's name, which on a glance
    // surface is noise: it is usually the folder you are already looking at,
    // and a path fragment beside "finished" reads as debris rather than as
    // information. "Claude needs you" keeps its subtitle, because there the
    // text is the reason it is asking.
    dismissAfter = 3;
  }

  // Merge by id: keep other posters' activities, drop our previous one and
  // anything already expired.
  let items = [];
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    feedPath, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
  }
  if (!Array.isArray(items)) items = [];
  const now = Date.now();
  items = items.filter(function (a) {
    return a && a.id && a.id !== 'claude-code'
      && (!a.endsAt || Date.parse(a.endsAt) > now - 2000);
  });

  const activity = { id: 'claude-code', icon: icon, title: title };
  // The app ignores an image it cannot read, so pointing at a missing file is
  // harmless — it simply falls back to the symbol.
  if (logoPath) activity.image = logoPath;
  // The window to bring forward when this is clicked in the panel.
  if (appPath) activity.app = appPath;
  if (dismissAfter !== null) {
    // dismissAfter says "no timer, and leave after this long". endsAt is
    // written alongside it purely so the entry expires from the file on its
    // own — without it a finished notice would linger in the feed and pop up
    // again the next time the app started.
    activity.dismissAfter = dismissAfter;
    activity.endsAt = stamp(now + dismissAfter * 1000);
  } else {
    activity.endsAt = stamp(now + waitSeconds * 1000);
  }
  if (subtitle) activity.subtitle = subtitle;
  items.push(activity);

  function stamp(ms) {
    return new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z');
  }

  $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
    .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
}
JXA
