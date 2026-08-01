# TODO

## Growl-replacement notifications (`notify.lua`)

Not started. This is a spec, not a description of existing code.

### Why

Growl is dead and nothing has replaced it. Notifications from ~/code/clipboard-scripts/ currently come from `osascript`:

- `display notification` — Notification Center. Transient, macOS decides how long, no stacking control, no click actions, easy to miss.
- `display alert` — persists until dismissed, but it's a **modal dialog that steals focus**. Matt hates it.

`hs.alert` (used throughout this config) is non-modal and styled, but auto-dismisses and doesn't stack meaningfully. `hs.notify` is just Notification Center again — no better than what we already have.

The gap: **non-modal, persistent-until-dismissed, stacked, styled**. That's what Growl did and what nothing else does.

### Consumer

`~/code/clipboard-scripts` — ~51 scripts, all notifying through one file, `lib/notify`. That file is deliberately the only implementation, so pointing it at Hammerspoon is a one-file change on that side.

Other callers should be assumed later. Design the CLI contract for general use, not just clipboard-scripts.

### Transport — already works, nothing to build

Both verified live:

- `hs.ipc` is required in `init.lua`, and `/opt/homebrew/bin/hs` → the app's `hs` binary.
- `hs -c '<lua>'` executes inside the running instance and returns stdout. `hs -c 'return 6*7'` → `42`.

**Interpolating the message into the Lua string is the trap.** Notification text is arbitrary clipboard content — quotes, backslashes, `]]`, newlines, emoji. Naive interpolation is both a syntax-error generator and a code-injection hole:

```
$ hs -c "hs.alert.show('it's \"quoted\" and ]] .. os.exit() .. [[')"
[string "..."]:1: ')' expected near '\'
```

Base64 is the fix, verified round-tripping quotes, backslashes, `]]`, newlines, em-dashes and emoji intact:

```bash
b64="$(printf '%s' "$message" | base64 | tr -d '\n')"   # tr is required; base64 wraps
hs -c "require('notify').show({ message = hs.base64.decode('$b64'), ... })"
```

Every string argument crossing the boundary must be base64-encoded. Enforce it in the wrapper so no caller can forget.

### Invocation arguments

Keep clipboard-scripts' existing CLI unchanged, so only `lib/notify`'s internals move:

```
notify [--sticky] MESSAGE...
```

The fuller contract a general wrapper should expose:

| argument | default | meaning |
| --- | --- | --- |
| `MESSAGE` (positional, may contain anything) | required | body text |
| `--title TEXT` | `Notice`; `lib/notify` sends the calling script's name | heading |
| `--sticky` | off | persist until dismissed; ignores `--duration` |
| `--duration SECONDS` | 5 | auto-dismiss delay when not sticky |
| `--icon PATH\|NAME` | none | leading image |
| `--id NAME` | calling script's name, via `lib/notify` | replace-in-place key: a second notification with the same id updates the first rather than stacking |
| `--private` | off | never written to disk; does not survive a reload or restart |

`--id` is the one Growl didn't have and we want: repeated `pb-*` invocations currently pile up identical banners.

Lua side:

```lua
local notify = require("notify")
notify.show({ message = "...", title = "Notice", sticky = false, duration = 5,
              icon = nil, id = nil, private = false })
notify.dismiss(id)      -- programmatic dismissal
notify.dismissAll()
```

### Decided

**Home — a Hammerspoon module, not a standalone menubar app.** The transport, config load, module pattern and test harness all exist here; none exist for a new app, which would also need its own build, signing, launch-at-login and update story. Blast radius is contained by keeping the module small and letting no error escape `notify.show`.

**Sticky notifications survive `hs.reload()` and a Hammerspoon restart, unconditionally and with no age cap.** They are durable state, not transient UI, so losing them to the auto-reloader mid-edit is unacceptable — and a sticky card still up after a week is either a machine that has been down for a week (in which case restoring matters most) or something deliberately left there. `hs.settings` is already used for this kind of thing (`init.lua:305`, caffeine state). Constraints:

- Persist an **absolute deadline**, not a remaining duration, or a reload mid-countdown either resets or eats the timer.
- `hs.shutdownCallback` fires on both reload *and* quit and cannot tell them apart, so restore-on-load is the mechanism — write state on every mutation (show / dismiss / expire), not on shutdown.
- **`--private` (Lua `private = true`) notifications are never written to disk** and die with the process. Persistence means notification bodies at rest in a plaintext plist, and `pb-pwgen-sticky` exists to display freshly generated passwords while `pb-peek-at-clipboard` shows whatever is in the clipboard — often a password moments after `pb-pwgen`. Those three callers set `--private`. Note the consequence: a reload destroys the whole Lua state, so a private notification does not survive a reload either — `--private --sticky` means "stays until I dismiss it, but a config reload takes it with it". Accepted; the alternative is passwords at rest in a plist.

**Substrate — `hs.canvas`, from the start.** `hs.alert` can persist (`seconds` non-number) and be closed by uuid, but it has **no mouse handling at all**, so a `✕` and hover-to-pause are unreachable; and its `atScreenEdge=1|2` modes *overlay* rather than stack, leaving only centre-screen for real stacking. `hs.canvas` gives `mouseCallback`, `clickActivating(false)` so a click doesn't pull Hammerspoon to the front, `windowBehaviors.canJoinAllSpaces` so stickies survive a space switch, and per-notification frames so we own stacking. `modal_commands.lua` is the working precedent in this repo. The cost is hand-rolled text measurement, wrapping and fades — the bulk of the module.

**Placement — top-right of `hs.screen.primaryScreen()`**, resolved at paint time. A placed notification never moves except to close a gap left above it.

**Stack — newest appended at the bottom, growing downward.** Newest-at-top would shove the whole stack down on every arrival, violating the never-moves rule. In MVP the stack simply runs off the bottom of the screen when it's too long; the path to seeing the rest is to deal with the ones in front of it.

**Long text — fixed card width, word wrap, capped line count, `… (+N more lines)` footer, no expansion.** Fixed width (not a fraction of screen width, not size-to-content) so a stack of cards reads as a column. `pb-peek-at-clipboard` sends the whole clipboard and goes sticky *because* it's long, so long+sticky is the common case — but it is a *peek*, and the full text is by construction still in the clipboard, so clipping is cheap.

**Every limit is configuration** (`configConsts`), not a literal in `notify.lua`: card width, max lines, default duration, stack gap, margins, font sizes.

**Dismissal — a small `✕`, a single-finger swipe right, or `⎋` while hovering. Clicking the card body does nothing.** Click is reserved for the later `clickAction`, and letting it dismiss now would train the wrong habit. Hovering a card pauses its auto-dismiss countdown, so a 5s notification you start reading at 4.5s is still readable. Cards swallow clicks to whatever is beneath them; that's accepted, and these three are the way out. No click-flick imitation of a swipe — either the real gesture or nothing.

**Swipe is a real trackpad gesture, via `hs.eventtap`.** `hs.canvas` reports only mouseDown/Up/Enter/Exit/Move, but `hs.eventtap.event.types.gesture` + `event:getTouches()` gives per-touch `identity`, `phase` (began/moved/ended/cancelled), force and normalized surface position. `Swipe.spoon` (mogenson) accumulates deltas per touch identity and reports `(direction, distance, id)` — the same technique. Single finger, matching macOS's own notification dismissal (verified live on an `osascript` banner). Details:

- Gesture events carry **no pointer location**; use `hs.mouse.absolutePosition()` to find which card the gesture started over.
- Start the tap when the stack becomes non-empty, stop it when the stack empties, so it isn't in the event path all day.
- Don't consume the event. The window under the pointer is our own canvas, so there's nothing beneath to protect.
- Thresholds are tuning constants → `configConsts`. Working definition, to be checked against Apple's if it is documented anywhere: the gesture must **begin over a card** (latch that card at touch-`began` — the pointer travels off the card mid-swipe, so continuous hit-testing would break it), travel rightward past a minimum but not beyond a maximum, and release, all inside a short time bound. Large changes in velocity-as-a-vector — speed or direction — abort it.
- **The card does not follow the finger** in the first implementation. It animates out only once the gesture completes. Following the finger with a spring-back is nicer and makes the threshold visible rather than hidden, but it is per-frame canvas work and not worth the first pass.
- **Magic Mouse is untested.** Expected to work — it is a multitouch surface — but unconfirmed. Test alongside the click-swallowing check.
- A plain non-multitouch mouse generates no gesture events at all, which is why `✕` and `⎋`-hover are not optional.

**`--id` replace-in-place — keep position, replace every attribute, reset the timer, pulse the card.** Position because it's the same item and the never-moves rule applies. Wholesale replacement rather than a merge, so the second call's `--sticky`/`--duration`/`--title` win outright with no ambiguity. Timer reset because a new event is new information. A brief border pulse because an in-place text swap on a card you weren't watching is otherwise invisible — the failure mode of replace-in-place. If the previous card with that id is already gone, the new one appends at the bottom as usual. Ids are one flat global namespace; callers namespace themselves and collisions are the caller's problem.

**`lib/notify` defaults `--id` to the calling script's name** (`pbclip.py` has `argv[0]`), fixing the pile-up of repeated `pb-*` banners across all ~51 scripts with no per-script change. The cost — two different results from the same script collapsing into one card — is a caller concern: a script wanting successive results to coexist passes its own unique id.

**Styling — monospace body, system-font title, palette follows system appearance.** Monospace (`SFMono-Regular`, as `modal_commands.lua` uses) is a simplification, not just a taste: `hs.canvas.minimumTextSize` and `hs.drawing.getTextDrawingSize` measure a string but neither accepts a wrapping width, so wrapping proportional text to a fixed-width card means repeated measurement of candidate lines. With a fixed character width, measured once, wrapping is arithmetic. It also suits the payloads — hashes, indent-aligned password blocks, and passwords where `l`/`1`/`I` and `O`/`0` must be distinguishable. The cost is that prose notifications look like terminal output.

`lib/notify` **defaults the title to the calling script's name** rather than `Notice`, so a card says which of the 51 scripts produced it. `notify.show` keeps `Notice` as its fallback for other callers. Appearance: `hs.host.interfaceStyle()` returns `"Dark"` or `nil`, so two palettes in `configConsts` chosen at paint time, the dark one anchored on `hs.alert`'s defaults (`{white=0, alpha=0.75}` fill, white stroke) so this looks like part of the config. Fades 0.15s each way, matching `hs.alert`.

**CLI wrapper — one implementation, in this repo, at `bin/notify`.** The contract is for general use, so it belongs with the notifier rather than inside clipboard-scripts. `bin/notify` locates `hs` absolutely, base64-encodes every string argument, and falls back to `osascript` itself. `clipboard-scripts/lib/notify` shrinks to: exec `bin/notify` if it exists, else the `osascript` it does today. Two trivial fallbacks, each local to the thing that can fail.

**Liveness pre-check, then fire-and-forget.** `hs -c` waits for the Lua to return, which is normally tens of milliseconds but hangs indefinitely if Hammerspoon is wedged — and non-blocking is a hard requirement. So: check the `hs` binary exists *and* `pgrep -x Hammerspoon` succeeds; if either fails, use `osascript`; otherwise fire `hs -c` in the background and exit 0 immediately. The residual failure is that a running-but-wedged Hammerspoon silently drops a notification. That is the right trade — the caller never blocks and never breaks.

**Testing — a pure layout core with a thin canvas renderer over it.** busted has no Hammerspoon APIs, only `spec_helper.lua`'s mocks, so the seam has to be deliberate: everything testable is arithmetic and bookkeeping, and it must not touch `hs.canvas`. Testable without the app: word wrapping and truncation, `… (+N more lines)` counting, stack frame arithmetic, gap-closing on dismissal, id replacement bookkeeping, timer deadline handling, persistence round-trip and the `private` exclusion, argument parsing and defaults. `spec_helper.lua` needs mocks added for `hs.canvas`, `hs.eventtap`, `hs.settings`, `hs.mouse`, `hs.screen`, `hs.base64`, `hs.host`. Add `notify` to `configConsts.modules_under_test` while building, so saving `notify.lua` runs specs instead of reloading.

### Build order

0. **Console prototype**, before committing to the design. Two unknowns: does a canvas with all mouse events disabled pass clicks through to the window beneath, and does `getTouches()` report a Magic Mouse?
1. **Module core** — `show` / `dismiss` / `dismissAll`, card rendering, fixed width, wrap and truncate, stack layout, auto-dismiss timers, hover-pause, `✕`, `⎋`-while-hovering.
2. **Transport** — `bin/notify`, base64, liveness check, `osascript` fallback; switch `clipboard-scripts/lib/notify` over. End-to-end and usable at this point.
3. **Identity and durability** — `--id` replace-in-place, persistence, `--private`.
4. **Swipe** — the gesture eventtap, started and stopped with the stack. First thing to cut if it fights back.

### Hard requirements

- **Never let a notification failure break the caller.** If Hammerspoon isn't running or `hs` isn't on `PATH`, fall back to `osascript` and still exit 0. Launchers run scripts with a bare `PATH`, so locate `hs` by absolute path, not via `PATH`. (`clipboard-scripts/lib/pbclip.py` already carries a `SEARCH_PATHS` tuple doing exactly this hunt.)
- **Non-blocking.** `display alert` blocks; the replacement must return immediately.
- **No error escapes `notify.show`.** This module shares a process with window management; a bug in it must not take that down.
- Follow the module pattern in `CLAUDE.md` (`local M = {}` … `return M`, metadata fields, `hs.logger.new()`), with tests in `spec/`.

### Out of scope / maybe later

- **Click-through-to-action.** No precedent in this config — `clickAction` is used nowhere — so it needs designing rather than copying.
- **Card follows the finger during a swipe**, with a spring-back below threshold and proportional fade.
- **Modal hotkey for keyboard-driven triage**: arrow up/down to highlight a card, right to dismiss it, left to trigger its `clickAction`.
- **Click the `… (+N more lines)` footer to expand the card in place**, up to screen height; click anywhere else still dismisses. `hs.canvas`'s `mouseCallback` reports which element was hit, so this doesn't depend on the `clickAction` work above.
- **Grouping similar notifications so they all fit.** The likeliest overflow is a poorly-considered tight loop, so the count may be very large but highly repetitive. First pass: group exact duplicates and show one card with a count badge. Later passes: cleverer grouping of near-duplicates.
- **`+N more` pill** at the foot of the stack, with queued notifications fading in as space frees.
- **Stranded notifications** if the primary display changes or disconnects. The primary display is the one holding the menubar (System Settings → Displays → Arrange). Since `primaryScreen()` is re-resolved at paint time, and macOS always designates some display primary, a Hammerspoon reload should recover a stranded stack. End-of-project cleanup note, not an MVP concern.
