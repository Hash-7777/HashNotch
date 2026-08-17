#!/usr/bin/env bash
#
# Wires Claude Code to your notch: after this, HashNotch shows a live activity
# the moment Claude finishes a reply or is waiting for your permission.
#
# What it does — nothing more:
#   1. Copies claude-code-hook.sh to ~/.hashnotch/ (the hook writes only the
#      local activities feed).
#   2. Registers it as a Stop + Notification hook in ~/.claude/settings.json,
#      backing the file up first. Safe to re-run; already-installed is a no-op.
#
# Uninstall: delete the two entries mentioning claude-code-hook.sh from
# ~/.claude/settings.json and remove ~/.hashnotch/claude-code-hook.sh.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# The hook always sits beside this script — in the repo's scripts/ folder, or in
# Contents/Resources/scripts inside the app bundle for anyone who downloaded the
# app rather than the source.
HOOK_SRC="$HERE/claude-code-hook.sh"
HOOK_DST="$HOME/.hashnotch/claude-code-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Cannot find claude-code-hook.sh next to this script ($HERE)." >&2
  exit 1
fi

mkdir -p "$HOME/.hashnotch" "$HOME/.claude"

# Explain the logo slot, because an empty folder explains nothing.
#
# The hook points the activity at ~/.hashnotch/logos/claude.png and the app
# quietly draws its checkmark symbol when no such file exists — which is correct
# behaviour and completely invisible, so "why is there no logo?" has had no
# answer anywhere. No mark is shipped: Claude's logo belongs to Anthropic, not
# to this app, and an app that ships someone else's brand has helped itself to
# it. Put one there yourself and the notch wears it.
LOGO_DIR="$HOME/.hashnotch/logos"
mkdir -p "$LOGO_DIR"

# Bring across the marks from the folder the app used under its previous name.
#
# The rename moved this folder, and a logo is something the user put here by
# hand — nothing re-downloads it, and nothing else on the machine knows it
# existed. Left behind, every tool's mark would silently turn back into a
# symbol on the first update, which looks like the app having forgotten
# something rather than a folder having moved.
#
# Copied, never moved, and never over a file that is already here: the old
# folder is left exactly as it was, so nothing is lost if this is re-run or if
# the old app is still installed.
#
# Written with plain `if`s rather than `cond && action`: under `set -e` an
# AND-list whose left side is false leaves a non-zero status behind, which is
# exactly the shape that once let a failure in this repo's build script be
# reported as success.
OLD_LOGO_DIR="$HOME/.hashdisland/logos"
if [ -d "$OLD_LOGO_DIR" ]; then
  carried=0
  for old in "$OLD_LOGO_DIR"/*; do
    if [ ! -f "$old" ]; then continue; fi
    name="$(basename "$old")"
    if [ "$name" = "README.txt" ]; then continue; fi
    if [ -e "$LOGO_DIR/$name" ]; then continue; fi
    cp "$old" "$LOGO_DIR/$name"
    carried=$((carried + 1))
  done
  if [ "$carried" -gt 0 ]; then
    echo "Carried $carried logo(s) over from the app's previous folder."
  fi
fi
if [ ! -f "$LOGO_DIR/README.txt" ]; then
  cat > "$LOGO_DIR/README.txt" <<'NOTE'
Logos shown on the notch instead of a symbol.

Drop a square PNG here named after the tool and the island will use it in place
of the built-in symbol for that tool's alerts:

    claude.png      shown for the Claude Code alerts

Anything readable works — PNG, JPEG, TIFF, HEIC, PDF — up to 4 MB. Small is
fine; it is drawn about 21 points wide. Remove the file and the symbol comes
back. Nothing here is downloaded or shipped with the app: these marks belong to
the tools they represent, so you supply the ones you want to see.
NOTE
fi

# Say out loud when an older hook is being replaced.
#
# The hook is COPIED here, so it does not follow app updates: an install done
# months ago keeps posting in the format that was current that day. That is how
# an alert already fixed in the app went on looking broken at the notch, with
# nothing anywhere saying why. Version in, version out, every time.
version_of() { [ -f "$1" ] && sed -n 's/^HOOK_VERSION=\([0-9][0-9]*\).*/\1/p' "$1" | head -1; }
OLD_VERSION="$(version_of "$HOOK_DST" || true)"
NEW_VERSION="$(version_of "$HOOK_SRC" || true)"

# Whether the two files actually differ, asked of the bytes rather than of the
# stamp. The version is written by hand and can therefore be forgotten: a hook
# was once changed without its number moving, so the installed copy and the new
# one both claimed to be v4 while behaving differently. The copy below is
# unconditional and always did the right thing — but the MESSAGE said "already
# current", which is the one sentence that stops somebody re-running this when
# they should.
DIFFERS=0
if [ -f "$HOOK_DST" ] && ! cmp -s "$HOOK_SRC" "$HOOK_DST"; then DIFFERS=1; fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

if [ -z "${OLD_VERSION:-}" ]; then
  echo "Installed the notch hook (v${NEW_VERSION:-?})."
elif [ "$OLD_VERSION" != "${NEW_VERSION:-}" ]; then
  echo "Updated the notch hook: v$OLD_VERSION to v${NEW_VERSION:-?}."
elif [ "$DIFFERS" -eq 1 ]; then
  echo "Refreshed the notch hook (v${NEW_VERSION:-?} — the copy on disk had drifted)."
else
  echo "The notch hook was already current (v${NEW_VERSION:-?})."
fi

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.hashnotch-backup-$(date +%s)"
  # Keep the three most recent and delete the rest of OUR OWN backups. This is
  # safe to re-run at any time, and re-running it is exactly what the README now
  # tells people to do after every update — without a limit, being helpful once
  # a version turns into a drawer full of near-identical files in a folder this
  # app does not own. Only the .hashnotch-backup-* names are ever touched.
  ls -t "$SETTINGS".hashnotch-backup-* 2>/dev/null \
    | tail -n +4 \
    | while IFS= read -r stale; do rm -f "$stale"; done
fi

RESULT="$(osascript -l JavaScript - "$SETTINGS" "$HOOK_DST" <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const path = argv[0];
  const hook = argv[1];

  let settings = {};
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    path, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try {
      settings = JSON.parse(ObjC.unwrap(existing));
    } catch (e) {
      return 'ERROR: ' + path + ' is not valid JSON - fix it first; nothing was changed.';
    }
  }
  if (typeof settings !== 'object' || settings === null || Array.isArray(settings)) {
    settings = {};
  }

  settings.hooks = settings.hooks || {};
  let added = 0;
  let removed = 0;
  const pairs = [['Stop', 'stop'], ['Notification', 'notification']];

  // True for any entry that runs THIS hook script, wherever it currently lives
  // or used to live. Matching on the script's file name rather than its full
  // path is what makes re-running this safe after the folder has moved: the
  // stale entry is dropped instead of left behind firing into nowhere.
  function isOurs(entry) {
    return JSON.stringify(entry || {}).indexOf('claude-code-hook.sh') !== -1;
  }

  for (let i = 0; i < pairs.length; i++) {
    const name = pairs[i][0];
    // The hook path is quoted: it contains the user's home directory, and a
    // home folder with a space in it would otherwise be split into two words
    // by the shell that runs this command.
    const command = '"' + hook + '" ' + pairs[i][1];
    const existing = settings.hooks[name] || [];
    const kept = existing.filter(function (entry) { return !isOurs(entry); });
    removed += existing.length - kept.length;

    kept.push({ hooks: [{ type: 'command', command: command }] });
    added++;
    settings.hooks[name] = kept;
  }

  $.NSString.alloc.initWithUTF8String(JSON.stringify(settings, null, 2))
    .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);

  return removed > 0
    ? 'Installed ' + added + ' hook(s), replacing ' + removed + ' older one(s).'
    : 'Installed ' + added + ' hook(s).';
}
JXA
)"

echo "$RESULT"
case "$RESULT" in
  ERROR*) exit 1 ;;
esac
echo "Claude Code will now post to your notch when it finishes or needs permission."
echo "(Restart any running Claude Code session so it picks up the new hooks.)"
