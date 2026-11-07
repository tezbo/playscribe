# Team alerts: an App Store build clears a leftover team=true (r052-team-alerts-clear)

Goal: team test pushes never reach an App Store user. Raised by Quinn on #313; blocker for external TestFlight and the App Store (coordinator, 7 Nov).
Gap: a tester who switched Team alerts on in TestFlight and then installs the App Store build keeps team=true on the relay record, because the App Store build never sends team.
Smaller alternative: do nothing (rejected: fails the quality bar). Larger: relay-side expiry of team flags (not needed, the client fix is small).
Decision: when the build does not show the toggle and the stored choice is on, registration sends team=false once; the stored choice is removed only after the relay answers 2xx, so a failed send is tried again next launch. A build that never chose sends nothing. Tests in PushRegistrarTests.
Weighed in: Quinn (flagged it), Iris (no UI change).
