# r053-open-portrait-tabbar-covers-last-row

Short form. Goal: in Open portrait the last row of a scrolling screen is never covered by the tab bar (Iris; v0.5.3 blocker, no known bug ships).
Smaller alternative: pad only the Library (rejected: Updates and Search end under the bar too). Do nothing: not allowed.
Decision: the one scroll-clearance rule that already keeps pages above the pill (`clearsMessages`) also keeps them above the tab bar band in Open portrait, 96 pt from the window bottom, the same line the pill sits on. It is measured from the view's own frame, so a screen the system already insets gets no extra padding. Pose comes from the container (flat, portrait), no device checks. Frame test: OpenPortraitTabBarTests (last row maxY <= tab bar minY at scroll end, std and AX5, Library and Updates).
Weighed in: Iris (found it), Quinn and Iris to sign on the Mac stills.
Learning: a floating bar over a scroll view is not an inset; measure the clearance against the bar's band, not the safe area.
