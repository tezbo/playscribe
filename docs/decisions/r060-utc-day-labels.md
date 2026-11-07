# r060-utc-day-labels

Short form (Quinn's #354 review). Goal: a relative label never disagrees with the printed UTC release date.
Gap: on main, "Out today" and the same-year check already use UTC helpers (sameUTCDay, sameUTCYear); two places still used the device calendar: the Upcoming "this week" window (startOfDay in the device zone) and the moved-date label's month and day (local formatting).
Smaller alternative: fix only the window (rejected: the moved-date label has the same bug and the same fix). Doing nothing: in zones around +13h a game due tomorrow UTC can sit in or out of "this week" against the date it prints.
Decision: `Date.isInUTCWeek(from:)` (today and the next six UTC days) for the window; the moved-date label formats in UTC. Test across Auckland, UTC and Pago Pago.
Weighed in: Quinn (raised it), Nadia (owner of the date rule).
Learning: when a rule says "UTC day", grep for every Calendar.current and local `.formatted(.dateTime...)` on release dates, not only the helper that was named in the review.
