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
#
# v10 is the tick that replaced the stars when a reply finishes. That change
# went out at v9 — the script changed and this number did not — so every copy
# installed before it claimed to be the same version while drawing something
# else, which is the precise failure this stamp exists to prevent. CI now
# refuses a push that changes this file without changing this number.
HOOK_VERSION=10

EVENT="${1:-stop}"
# A logo to show instead of the symbol, if one has been placed here. Claude's
# own mark is not shipped with this app — drop a PNG at this path and the notch
# uses it; without it the checkmark symbol is shown exactly as before.
LOGO="$HOME/.hashnotch/logos/claude.png"
PAYLOAD="$(cat 2>/dev/null || true)"
FEED="$HOME/.hashnotch/activities.json"
mkdir -p "$(dirname "$FEED")"

# "Claude needs you" waits rather than dismissing itself, because it is asking
# for something — and until now the only thing that took it down was answering
# AND Claude then finishing its turn, which can be minutes later. So it sat on
# the notch long after it had been dealt with.
#
# `clear` is fired the moment the session moves again: a prompt submitted, or a
# tool about to run because permission was granted. It takes down a request and
# leaves everything else alone.
#
# It is registered on events that fire constantly, so it gets out of the way
# before doing anything expensive: no feed, or no entry of ours in it, and this
# exits without starting a subprocess at all.
# Tools you want to be asked about ON THE NOTCH rather than in the window,
# one name per line — Bash, Write, Edit, WebFetch. No file, no interception:
# the whole feature is inert until you write it, and it stays inert for every
# tool you leave out of it.
ASK_LIST="$HOME/.hashnotch/ask-tools.txt"
ASK_SECONDS="${HASHNOTCH_ASK_SECONDS:-20}"

# What the tool is called, out of the payload PreToolUse hands us. Read with a
# plain match rather than a JSON parser because this runs before every single
# tool call, and the answer is only used to decide whether to do any real work.
tool_name() {
  printf '%s' "$PAYLOAD" | sed -n 's/.*"tool_name" *: *"\([^"]*\)".*/\1/p' | head -1
}

# Whether this is a tool the owner asked to be consulted about.
wants_asking() {
  [ -f "$ASK_LIST" ] || return 1
  local name="$1"
  [ -n "$name" ] || return 1
  grep -qxF "$name" "$ASK_LIST" 2>/dev/null
}

TOKEN=""
TOOL=""
if [ "$EVENT" = "clear" ]; then
  HAS_OURS=no
  if [ -f "$FEED" ] && grep -q '"claude-code"' "$FEED" 2>/dev/null; then
    HAS_OURS=yes
  fi
  TOOL="$(tool_name)"
  if [ "$HAS_OURS" = "yes" ]; then
    # A request was standing and this tool call is the session moving again —
    # take it down, and do not turn round and ask about the very thing that was
    # just approved.
    :
  elif wants_asking "$TOOL"; then
    # Nobody can answer a question if the app is not up. Asking anyway would
    # stall the tool call for the whole waiting period and then fall back to
    # the ordinary prompt — slower than never having asked.
    if pgrep -x HashNotch >/dev/null 2>&1; then
      EVENT="ask"
      TOKEN="ask-$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
      [ -n "$TOKEN" ] || exit 0
    else
      exit 0
    fi
  else
    exit 0
  fi
fi

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
osascript -l JavaScript - "$FEED" "$EVENT" "$PAYLOAD" "$LOGO" "$APP" "$TOKEN" "$TOOL" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  const event = argv[1];
  const logoPath = argv[3] || '';
  const appPath = argv[4] || '';
  const token = argv[5] || '';
  const toolName = argv[6] || '';
  let payload = {};
  try { payload = JSON.parse(argv[2] || '{}'); } catch (e) {}

  // "Finished" has already happened, so it is a notice: it shows for a moment
  // and leaves, with no timer counting down beside it. "Needs you" is a
  // standing request — it waits, because dismissing it after a few seconds
  // would hide the very thing it is asking you to deal with.
  // A question the notch can answer. Posted with a token; the app files the
  // answer against that token and the shell below collects it.
  if (event === 'ask' || event === 'clear-ask') {
    let items = [];
    const existing = $.NSString.stringWithContentsOfFileEncodingError(
      feedPath, $.NSUTF8StringEncoding, null);
    if (existing && !existing.isNil()) {
      try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
    }
    if (!Array.isArray(items)) items = [];
    items = items.filter(function (a) { return a && a.id && a.id !== 'claude-ask'; });

    if (event === 'ask') {
      // What is actually about to happen, in as few words as carry the
      // decision. A permission question you cannot see the substance of is
      // one you answer by habit, which is the same as not being asked.
      let detail = '';
      try {
        const input = (payload && payload.tool_input) || {};
        detail = String(input.command || input.file_path || input.url || input.path || '');
      } catch (e) {}
      if (detail.length > 90) detail = detail.slice(0, 89) + '…';
      const activity = {
        id: 'claude-ask',
        icon: 'hand.raised.fill',
        title: 'Allow ' + (toolName || 'this') + '?',
        asks: token,
        endsAt: stamp(Date.now() + 120000),
      };
      if (detail) activity.subtitle = detail;
      if (appPath) activity.app = appPath;
      items.push(activity);
    }

    $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
      .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
    return;
  }

  // Take down a standing request, and only that. A notice that has finished
  // keeps its few seconds — it is already leaving on its own, and cutting it
  // short would mean the answer you just gave erased the news that the last
  // one had finished.
  if (event === 'clear') {
    let items = [];
    const existing = $.NSString.stringWithContentsOfFileEncodingError(
      feedPath, $.NSUTF8StringEncoding, null);
    if (existing && !existing.isNil()) {
      try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
    }
    if (!Array.isArray(items)) items = [];
    const before = items.length;
    items = items.filter(function (a) {
      if (!a || a.id !== 'claude-code') return true;
      // A request is the kind that waits: a deadline and no dismissal.
      const waiting = a.endsAt && (a.dismissAfter === undefined || a.dismissAfter === null);
      return !waiting;
    });
    if (items.length !== before) {
      $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
        .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
    }
    return;
  }

  let icon, title, subtitle, dismissAfter = null, waitSeconds = null;
  if (event === 'notification') {
    icon = 'hand.raised.fill';
    title = 'Claude needs you';
    subtitle = String(payload.message || '').slice(0, 120) || null;
    waitSeconds = 1800;
  } else {
    // A tick: one open stroke, sweeping up to the right.
    //
    // Stars were here, on the reasoning that "finished" is already in the
    // title and the notch is already green, which leaves the symbol free to
    // say WHAT finished rather than repeat that it is done. That trade was the
    // wrong way round. Stars are the house mark of every AI product at once,
    // so they name the category and not the event — and at 21 points a
    // multi-pointed glyph is scattered light rather than a shape. Rendered
    // against the real badge with a line through its centre, the mass of
    // `sparkles` sits visibly off to one side: two stars of different sizes
    // have no balance point to centre on, so no amount of centring the frame
    // can make it look centred.
    //
    // A single stroke has one. Repeating the colour costs nothing here: the
    // green is a hairline around the notch and this is a shape inside it, and
    // the two agreeing is what makes them read as one event rather than two.
    // The filled variants stay rejected for the reason they always were — a
    // tick in a bubble, in a seal, in a speech mark is a solid glyph inside a
    // solid disc, which reads as heavy at this size and pushes the title onto
    // a second line it does not have room for.
    icon = 'checkmark';
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

# ── Waiting for the answer ───────────────────────────────────────────────────
#
# Only ever reached for a tool the owner listed. The question is now on the
# notch; this waits for it to be answered and tells Claude Code what was said.
#
# Every way out of here is safe:
#   answered      -> allow or deny, exactly as clicked
#   not answered  -> "escalate", which is Claude's own prompt, exactly as if
#                    this hook had never run
#   anything else -> nothing printed at all, which is also the ordinary flow
#
# The answer is left in this app's own preferences rather than in a file — the
# app promises it writes none — and a read costs about five milliseconds, so
# looking four times a second for twenty seconds is cheaper than the osascript
# call that posted the question.
if [ "$EVENT" = "ask" ] && [ -n "$TOKEN" ]; then
  DECISION=""
  DEADLINE=$(( $(date +%s) + ASK_SECONDS ))
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    # `|| true` matters: there is no answers key until the first answer is ever
    # given, `defaults read` fails when it is missing, and this script runs
    # under `pipefail` — without it the very first question kills the hook
    # before it can wait for anything.
    ANSWER="$({ defaults read com.hashnotch.app hashnotch.answers.v1 2>/dev/null || true; } \
      | sed -n "s/^ *\"*${TOKEN}\"* *= *\"*\([a-z][a-z]*\).*/\1/p")"
    case "$ANSWER" in
      allow|deny) DECISION="$ANSWER"; break ;;
    esac
    sleep 0.25
  done

  # Take the question down whichever way it went — it has been answered, or it
  # is about to be asked again in the window, and either way it is stale.
  osascript -l JavaScript - "$FEED" "clear-ask" "" "" "" "" "" >/dev/null 2>&1 <<'JXA2'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  let items = [];
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    feedPath, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
  }
  if (!Array.isArray(items)) items = [];
  const kept = items.filter(function (a) { return a && a.id && a.id !== 'claude-ask'; });
  if (kept.length !== items.length) {
    $.NSString.alloc.initWithUTF8String(JSON.stringify(kept, null, 2))
      .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
  }
}
JXA2

  case "$DECISION" in
    allow)
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Allowed from the notch"}}\n'
      ;;
    deny)
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied from the notch"}}\n'
      ;;
    *)
      # Nobody answered. Hand it back to Claude Code to ask in its own window,
      # which is what would have happened without any of this.
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"escalate","permissionDecisionReason":"No answer on the notch"}}\n'
      ;;
  esac
fi
