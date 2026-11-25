#!/usr/bin/env python3
"""bug-ui-runner-terminate-flake: decide whether a failed UI test run earns one retry.

Reads `xcrun xcresulttool get test-results tests --path X.xcresult` JSON on stdin. A retry is earned only when EVERY
failed test case failed with nothing but a runner app-lifecycle error: XCTest could not start the app, stop it, or get a
snapshot of it in time. Those errors come from the simulator, not from an assertion; on 25 Nov they hit a different test on
each of three ui attempts at one head (45592816738: testFirstRunWelcomeAndSkip, RailSetTests testClosedStd, GameToGameTests),
and main's run 45583465960 too. An assertion failure anywhere means no retry: the run stays red as it is.

Exit 0 and print one -only-testing argument per lifecycle-failed test: retry exactly those, once.
Exit 1: at least one failure is not a lifecycle error (or carries no message), so no retry.
Exit 2: no failed test case found.
`--self-test` checks the classifier against fixtures shaped like the real errors.
"""
import json
import re
import sys

BUNDLE = "PlayscribeUITests"

# The exact runner errors seen, and nothing broader. A wrong value, a missing element or a timeout in a test's own
# waitForExistence never matches.
LIFECYCLE = re.compile(
    r"Failed to terminate co\.codeconnectors\.playscribe"
    r"|Application '?co\.codeconnectors\.playscribe'? does not have a process ID"
    r"|Failed to launch co\.codeconnectors\.playscribe"
    r"|Failed to get matching snapshots?: Timed out while evaluating UI query"
)


def failed_cases(node, out):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        msgs = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
        out.append((node.get("nodeIdentifier") or node.get("name", ""), msgs))
    for c in node.get("children", []):
        failed_cases(c, out)
    return out


def classify(results):
    cases = []
    for n in results.get("testNodes", []):
        failed_cases(n, cases)
    if not cases:
        return 2, []
    retry = []
    for ident, msgs in cases:
        if not msgs or not all(LIFECYCLE.search(m) for m in msgs):
            return 1, [ident]
        retry.append(ident)
    return 0, retry


def only_testing(ident):
    ident = re.sub(r"\(\)$", "", ident)
    return f"-only-testing:{BUNDLE}/{ident}"


def self_test():
    def case(ident, *msgs, result="Failed"):
        return {"nodeType": "Test Case", "nodeIdentifier": ident, "result": result,
                "children": [{"nodeType": "Failure Message", "name": m} for m in msgs]}

    def run(*cases):
        return {"testNodes": [{"nodeType": "Test Plan", "children": [{"nodeType": "Unit test bundle", "children": [
            {"nodeType": "Test Suite", "children": list(cases)}]}]}]}

    term = "RailSetTests.swift:125: Failed to terminate co.codeconnectors.playscribe:27492: Failed to terminate co.codeconnectors.playscribe:0"
    pid = "Application 'co.codeconnectors.playscribe' does not have a process ID"
    snap = "RailSetTests.swift:21: Failed to get matching snapshots: Timed out while evaluating UI query."
    edge = "GameToGameTests.swift:63: XCTAssertFalse failed - edge swipe: still on the second game"
    wait = "RailSetTests.swift:21: XCTAssertTrue failed - the game page did not load"
    passed = case("RailSetTests/testClosedAX5()", result="Passed")
    checks = [
        (run(case("RailSetTests/testClosedStd()", term), passed), (0, ["RailSetTests/testClosedStd()"])),
        (run(case("ReleaseFeatureTests/testFirstRunWelcomeAndSkip()", pid)), (0, ["ReleaseFeatureTests/testFirstRunWelcomeAndSkip()"])),
        (run(case("RailSetTests/testClosedLandscapeStd()", snap)), (0, ["RailSetTests/testClosedLandscapeStd()"])),
        # An assertion beside a lifecycle error in the same test: no retry.
        (run(case("GameToGameTests/testBack()", edge, term)), (1, ["GameToGameTests/testBack()"])),
        # One lifecycle failure and one assertion failure in another test: no retry for either.
        (run(case("RailSetTests/testClosedStd()", term), case("GameToGameTests/testBack()", edge)), (1, ["GameToGameTests/testBack()"])),
        # The test's own wait timing out is an assertion, not a runner error.
        (run(case("RailSetTests/testClosedStd()", wait)), (1, ["RailSetTests/testClosedStd()"])),
        (run(case("RailSetTests/testClosedStd()")), (1, ["RailSetTests/testClosedStd()"])),
        (run(passed), (2, [])),
    ]
    bad = 0
    for i, (results, want) in enumerate(checks):
        got = classify(results)
        if got != want:
            bad += 1
            print(f"self-test {i}: got {got}, want {want}")
    assert only_testing("RailSetTests/testClosedStd()") == "-only-testing:PlayscribeUITests/RailSetTests/testClosedStd"
    print("self-test:", "FAIL" if bad else f"pass ({len(checks)} cases)")
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    code, idents = classify(json.load(sys.stdin))
    if code == 0:
        print(" ".join(only_testing(i) for i in idents))
    else:
        print(" ".join(idents), file=sys.stderr)
    sys.exit(code)
