#!/usr/bin/env bash
#
# Post a live activity to HashNotch. Any app, script, or Apple Shortcut can
# do the same by writing ~/.hashnotch/activities.json (an array of
# activities). Activities MERGE by id — posting replaces your previous activity
# with the same id and leaves other posters' activities alone.
#
# Two kinds. A COUNTDOWN is something still happening, and shows its time left:
#   ./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
#      title ------------------^  subtitle -----^          icon ---^  ^-- minutes left
#   ./scripts/post-activity.sh --id build "Building app" "release" hammer 10
#
# A NOTICE is something that already happened. It draws no timer and leaves on
# its own after a few seconds:
#   ./scripts/post-activity.sh --notice 3 "Build finished" "release" hammer
#      seconds to show ---------------^
#
# Show a logo instead of the symbol (any readable image):
#   ./scripts/post-activity.sh --image ~/logo.png --notice 3 "Build finished"
#
# Clear all activities:
#   ./scripts/post-activity.sh --clear
#
set -euo pipefail

FEED="$HOME/.hashnotch/activities.json"
mkdir -p "$(dirname "$FEED")"

if [ "${1:-}" = "--clear" ]; then
  echo "[]" > "$FEED"
  echo "Cleared $FEED"
  exit 0
fi

ID="cli-1"
if [ "${1:-}" = "--id" ]; then
  ID="${2:?--id needs a value}"
  shift 2
fi

# An optional logo. The app ignores anything that is not a readable image, so a
# wrong path costs nothing — it simply falls back to the symbol.
IMAGE=""
if [ "${1:-}" = "--image" ]; then
  IMAGE="${2:?--image needs a path}"
  shift 2
fi

# A notice is measured in seconds and shows no timer; a countdown is measured in
# minutes and does. NOTICE_SECONDS is empty for a countdown.
NOTICE_SECONDS=""
if [ "${1:-}" = "--notice" ]; then
  NOTICE_SECONDS="${2:?--notice needs a number of seconds}"
  shift 2
  if ! [[ "$NOTICE_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "notice seconds must be a whole number (got: $NOTICE_SECONDS)" >&2
    exit 1
  fi
fi

TITLE="${1:-Activity}"
SUBTITLE="${2:-}"
ICON="${3:-app.badge}"
MINUTES="${4:-15}"

if ! [[ "$MINUTES" =~ ^[0-9]+$ ]]; then
  echo "minutes must be a whole number (got: $MINUTES)" >&2
  exit 1
fi

# All JSON handling in JavaScript-for-Automation (always present on macOS).
# Values pass as argv, so quotes/backslashes/newlines in titles are safe.
osascript -l JavaScript - "$FEED" "$ID" "$ICON" "$TITLE" "$SUBTITLE" "$MINUTES" "$NOTICE_SECONDS" "$IMAGE" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  const noticeSeconds = argv[6] ? parseInt(argv[6], 10) : null;

  let items = [];
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    feedPath, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
  }
  if (!Array.isArray(items)) items = [];
  const now = Date.now();
  items = items.filter(function (a) {
    return a && a.id && a.id !== argv[1]
      && (!a.endsAt || Date.parse(a.endsAt) > now - 2000);
  });

  const activity = { id: argv[1], icon: argv[2], title: argv[3] };
  // Ignored by the app unless it names a readable image, so a wrong path just
  // falls back to the symbol.
  if (argv[7]) activity.image = argv[7];
  if (noticeSeconds !== null) {
    // dismissAfter means "no timer, and leave after this long". endsAt goes in
    // alongside it so the entry expires from the file on its own, rather than
    // lingering and reappearing the next time the app starts.
    activity.dismissAfter = noticeSeconds;
    activity.endsAt = stamp(now + noticeSeconds * 1000);
  } else {
    activity.endsAt = stamp(now + parseInt(argv[5], 10) * 60000);
  }
  if (argv[4]) activity.subtitle = argv[4];
  items.push(activity);

  $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
    .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);

  function stamp(ms) {
    return new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z');
  }
}
JXA

if [ -n "$NOTICE_SECONDS" ]; then
  echo "Posted notice '$ID' to $FEED (shows for ${NOTICE_SECONDS}s, no timer)"
else
  echo "Posted activity '$ID' to $FEED (ends in $MINUTES min)"
fi
