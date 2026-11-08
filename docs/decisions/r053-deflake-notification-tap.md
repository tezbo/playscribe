# r053-deflake-notification-tap

Short form. Goal: testNotificationTapOpensRelease passes on a fresh simulator the first time, so a red run means a real N-6 break (v0.5.3 tag blocker).
Smaller alternative: a longer wait for the Open button (rejected: the button was found, then gone). Do nothing: not allowed, a flaky gate hides real failures.
Cause (from the failure text, not reproduced here): "No matches for 'Open' in swipe-action-button-identifier" at 7161347. The button existed when found and was gone when `.tap()` resolved it a second time. A first row tap that does bring the app up also hides the slide-out. The first run on a fresh sim failed after 132 s; the second passed.
Decision: tapOpenIfRevealed stops as soon as the app is in front, reads the button from one snapshot (which throws, not fails, when it is gone), and taps that point on SpringBoard. Test-only; no app code changes.
Weighed in: Quinn signs.
Learning: never resolve a SpringBoard element twice; read its frame once and tap the point.
