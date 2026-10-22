# M3 physical-device validation — pending

No physical-camera or reference-meter results have been recorded. Simulator tests
and a successful device build do not satisfy M3's hardware exit criterion.

Run on a signed physical iPhone with no launch arguments. Record the iPhone model,
iOS version, lighting, steps, and actual result for each check below. Calibration
and persisted settings belong to M4; all M3 camera readings are uncalibrated.

| Check | Expected behavior | Result |
| --- | --- | --- |
| Fresh permission grant | Explanation, system prompt, preview, settling, then Live · Stable · Uncalibrated | Pending |
| Denied/restricted permission | No recommendation; Settings/manual EV offered; returning after enabling permission reconnects | Pending |
| Evenly lit target | Timestamp updates at about 4 Hz; values repeat without claiming reference-meter accuracy | Pending |
| Changing light / motion / flicker | Current recommendation disappears while unsettled; after 3 s, explanation replaces spinner; automatic recovery | Pending |
| Bright/dark exposure limits | Unavailable if phone AE cannot reach its target; no plausible default EV | Pending |
| Preview taps, center reset | Tap biases intended area with portrait/aspect-fill crop; reticle follows tap and resets; center button works with VoiceOver | Pending |
| Hold / manual / Resume | Timestamp freezes and provenance stays explicit; capture stops; settings still recalculate; Resume settles again | Pending |
| Repeated background / foreground | Camera stops when inactive, restarts once when active, no old live recommendation | Pending |
| Camera interruption | Reading becomes unavailable; interruption end reconnects and settles; runtime failure offers Retry | Pending |
| Small screen / large text / VoiceOver | Controls reachable, states spoken, center action available even with preview hidden | Pending |
| Reference-meter comparison | Record raw EV100, meter EV100, and residual under daylight, tungsten, and LED; no calibration accuracy claim yet | Pending |

Watch for incorrect tap mapping, timestamp stalls, persistent settling in steady
light, and readings that appear stable while the phone is exposure-limited. Those
require device evidence before adjusting the initial quality thresholds.
