# Contributing

Thanks for looking. This is a small, opinionated app, and the bar for changes is
mostly about evidence rather than style.

## Before anything else

```sh
git config core.hooksPath .githooks
```

Once per clone. Git does not carry hooks across a clone — deliberately, since a
hook is code that would otherwise run on somebody's machine without their
having read it. `.githooks/pre-commit` refuses a commit carrying a secret, a
`*.local.md` note, or build output. It judges only what is staged, and it can be
overridden with `--no-verify` when you are sure.

Then, before every push:

```sh
swift build                 # must be clean, and warning-free
swift run HashNotchChecks # must pass, all of them
```

Both are the gate, and they are yours to run — nothing catches a broken push for
you.

The same two commands run again on GitHub (`.github/workflows/build.yml`) for
every **push to main** and every **pull request**, and on demand from the
Actions tab. This repository is public, so GitHub's hosted runners cost nothing
and a second machine is worth having on every change — both to catch what one
machine agrees with itself about, and so that anybody reading the repository can
see whether what is on main builds. That job also builds the release
configuration, assembles and verifies the `.app`, and checks that the README's
"checks passing" badge still matches the number that actually ran.

## The one rule that matters

**Measure before you claim.** Nearly every real bug in this app's history was a
plausible assumption nobody checked:

- The storage readout was wrong because it asked macOS "how much could be freed"
  instead of "how much is free", and both sound like the same question.
- Artwork was believed impossible for most apps because one MediaRemote call
  withholds it — a different call returns it.
- A "verified" claim rested on a build command that silently recompiled nothing.

If a change rests on how something behaves, show the measurement in the commit
message. "Should work" is the phrase that costs the most time later.

## Adding an indicator

Every capability is a self-contained module. The core never imports a feature
and never learns what one does.

1. Create `Sources/Feature<Name>/` with a type conforming to `NotchFeature`.
2. Add the target in `Package.swift`, depending only on `HashNotchKit`.
3. Add one line to `Sources/HashNotch/FeatureManifest.swift`.

Where it appears on a fresh install comes from `FeatureRegistry.defaultOrder`,
not from where you put it in the manifest — a feature that is not named there
goes to the end, which is what a new one should do.

Two things a feature must honour:

- **Off means off.** Stopping must stop the *reading*, not just the drawing. A
  feature that is switched off opens no files, runs no subprocess, and can
  trigger no permission prompt.
- **Panel-only work belongs to the panel.** If a readout is only visible inside
  the panel, sample it with `VisibleSampler` so it costs nothing while shut.

## Tests

`Sources/HashNotchChecks` is the whole suite: a plain executable, because this
machine has Command Line Tools only and no XCTest.

Write checks against **pure functions**, and extract one if there isn't a
suitable one — most of the bugs here were in a decision buried in a view body,
and pulling that decision out is usually the fix as well as the test. A check
that constructs a fixture and then asserts things about that same fixture is
worse than none; it passes forever regardless of the code.

Checks must leave nothing behind. If yours needs a settings store, it gets a
throwaway domain, and the sweep at the end of the run removes it.

## Commits

- One logical change each.
- Say **why**, not just what. The reasoning is the part that is expensive to
  reconstruct later.
- If you fixed something, say what it did wrong and how you know it is fixed.
- No AI co-author trailers.

## What is deliberately out of scope

- **Anything that reads the screen or synthesises clicks.** Accessibility is
  used for exactly three key presses — play/pause, next, previous — and that
  narrowness is what makes the permission defensible.
- **Clipboard history.** It contradicts the whole position of the app.
- **Ad blocking or skipping**, for the same reason as the first point.
- **Naming apps to support them.** Ask the system what is playing or what has
  the microphone; a list is wrong for everything not on it. The one exception in
  the codebase is documented with its reason beside it.

## Licence

This project is under the **GNU General Public License v3 or later**. By
contributing you agree your work goes out under the same terms.

In plain terms: anyone may use, read, change and share this. If they distribute
something built on it, that has to be free too, with its source available. That
is deliberate — an app whose whole claim is that you can check what it does
should not be forkable into something you cannot.
