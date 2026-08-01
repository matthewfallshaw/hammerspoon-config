# TODO

## Notifications (`notify/`)

Built and in use. `bin/notify --help` is the CLI contract; `notify/layout.lua`, `notify/card.lua` and `notify/gesture.lua` carry their own documentation, and every limit is in `configConsts.notify`.

Still open:

- **Swipe thresholds are untuned.** The five constants in `configConsts.notify.swipe` were chosen without a finger ever touching the pad. Adjust by feel; `enabled = false` turns the gesture off. Swipe is trackpad-only — a Magic Mouse emits no gesture events at all, which is why `✕` and `⎋`-while-hovering are not optional.
- **Emoji are about 2.2 columns wide**, but wrapping counts every codepoint as one, so a line containing them overruns the card and is clipped rather than re-wrapped. Fixable with a codepoint-range width table if it ever annoys.

### Maybe later

- **Click-through-to-action.** No precedent in this config — `clickAction` is used nowhere — so it needs designing rather than copying. Clicking the card body deliberately does nothing today, to leave that click free.
- **Card follows the finger during a swipe**, with a spring-back below threshold and proportional fade. Makes the threshold visible rather than hidden; costs per-frame canvas work.
- **Modal hotkey for keyboard-driven triage**: arrow up/down to highlight a card, right to dismiss it, left to trigger its `clickAction`.
- **Click the `… (+N more lines)` footer to expand the card in place**, up to screen height. `mouseCallback` already reports which element was hit, so this doesn't depend on the `clickAction` work above.
- **Grouping similar notifications so they all fit.** The likeliest overflow is a poorly-considered tight loop, so the count may be very large but highly repetitive. First pass: group exact duplicates behind one card with a count badge. Any policy about an over-long stack belongs here — there is deliberately no cap until then, because the column simply runs off the bottom and cards flow back up as those above them go.
- **`+N more` pill** at the foot of the stack, with queued notifications fading in as space frees.
- **Stranded notifications** if the primary display changes or disconnects. `primaryScreen()` is re-resolved at paint time and macOS always designates some display primary, so a reload should recover a stranded stack.
