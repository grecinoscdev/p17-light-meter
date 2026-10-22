# M3 physical-device validation — pending

The user reports successful app operation on an iPhone 16 Pro Max, before the
framing correction. Detailed lifecycle and reference-meter results remain pending.
The original green guide matched the PENTAX view at 3.2 m versus 2.2 m with the
PENTAX. The corrected preview passed its simulator geometry/regression tests and
an unsigned iPhone build on October 22, 2026. It has not yet been compared against
the physical camera after the correction.

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


For the framing recheck, compare the same two edge landmarks inside the green guide
and the PENTAX bright-frame lines, with both devices at the same marked position
and orientation. Repeat near 2.2 m and with a more distant scene. Record whether
the app shows more or less at the top/bottom and sides. Also tap an off-center
landmark to confirm that exposure weighting follows the displayed image. Optical
viewfinder parallax means close-up agreement is not a guarantee of film framing.
