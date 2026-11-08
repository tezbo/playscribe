# r053-deflake-notification-tap

Short form. Goal: testNotificationTapOpensRelease passes on a fresh simulator the first time, so a red run means a real N-6 break (v0.5.3 tag blocker).
Smaller alternative: a longer wait for the Open button (rejected: the button was found, then gone). Do nothing: not allowed, a flaky gate hides real failures.
Cause (from the failure text, not reproduced here): "No matches for 'Open' in swipe-action-button-identifier" at 7161347. The button existed when found and was gone when `.tap()` resolved it a second time. A first row tap that does bring the app up also hides the slide-out. The first run on a fresh sim failed after 132 s; the second passed.
Decision: tapOpenIfRevealed stops as soon as the app is in front, reads the button from one snapshot (which throws, not fails, when it is gone), and taps that point on SpringBoard. Test-only; no app code changes.
Weighed in: Quinn signs.
Learning: never resolve a SpringBoard element twice; read its frame once and tap the point.

Update (c4d2fae failed twice on a fresh sim on the Mac): the failure moved earlier, to "no banner and no row after 3 pulls; app says: qa-schedule: none". That "none" was not evidence: the test relaunched the app after the cold terminate, so it read a new process's empty log. Two changes. The app's QA schedule log now also reports the notification authorization status ("auth 2" = authorized; INTERNAL builds only). The test keeps accepting the permission prompt for up to 30 s until the app reports a status, stops with a plain message when it is denied, and on the cold failure path reports the log it read before the terminate. If a fresh-sim run now fails, the message says whether permission, scheduling or delivery is the broken step.
Learning: a probe that restarts the thing it probes proves nothing; read the state before you end the process.
