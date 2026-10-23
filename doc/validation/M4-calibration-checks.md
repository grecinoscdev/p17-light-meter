# M4 physical calibration and persistence checks — pending

No trusted reference-meter readings have been supplied. The user's successful iPhone 16 Pro Max capture/framing comparison is separate evidence and does not validate exposure accuracy.

Run on a signed iPhone without `--demo-meter`, `--reference-scenario`, or `--isolated-settings`.

1. Change mode, PENTAX ISO, EC, target aperture, grid, and film-box ISO. Add an owned fractional filter, enable My filters, and select it. Close/relaunch the app; ISO/EC/aperture/grid/filter settings and selection should restore, but a scene reading should not. Mode must start in P / Program and the guide in portrait.
2. Check an empty owned list: recommendations must not use unowned filters. Removing the selected filter should restore automatic selection. Film-box ISO mismatch should warn without changing calculations.
3. Under steady light, fill the metering area with an evenly lit neutral target. Use a trusted reflected meter set to ISO 100, without ND on the phone. Record meter model, iPhone model, iOS, illumination, target, raw phone EV100, and reference EV100.
4. Press Read Scene, wait for a measured result, then open Calibration, choose Use measured scene, and enter the reference, and check `offset = reference − raw`. Keep target and light unchanged, and do not take a different reading before saving. Save within five minutes; the corrected comparison should equal the reference. Relaunch and check the correction remains active with the same camera configuration.
5. Repeat independent comparisons at several light levels under daylight, tungsten, and LED. Record raw, correction, corrected EV100, reference, residual (`corrected − reference`), and observed temporal variation separately. Do not treat one saved point as validation across conditions.
6. Manual/simulated/unsettled/expired readings must not enable calibration capture. Manual EV never receives a correction. A measured camera snapshot retains its correction and timestamp while preview continues; scene changes do not replace it. Press Read Scene for a new measurement. Background/foreground must preserve the snapshot without taking another reading.
7. Reset the reference correction; measured EV should return to raw. Reset all saved data; defaults should return and owned filters/calibration should be empty. Relaunch to verify reset persists.
8. Check all new screens with large Dynamic Type and VoiceOver. Capture, entry, Save, Reset, ownership toggles, and custom-filter removal must remain reachable and understandable.

| Date / device / iOS | Meter / illumination / target | Raw EV100 | Offset EV | Corrected EV100 | Reference EV100 | Residual EV | Variation / notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pending | | | | | | | |

Automated tests cover context mismatch, schema/corruption handling, sign, repeated application, saved restoration/reset, inventory restrictions, and simulated/manual rejection. Actual illumination-dependent accuracy and hardware lifecycle remain unverified.
