import Testing
@testable import Playscribe

struct VerificationExplainerTests {
    @Test func everyTagHasACopyAndNoSourceNames() {
        for v in Verification.ladder {
            #expect(!v.tagName.isEmpty && !v.meaning.isEmpty)
            let text = (v.tagName + v.meaning).lowercased()
            #expect(!text.contains("http") && !text.contains("steam") && !text.contains("playstation blog"))
        }
        #expect(Verification.ladder.first == .official)
    }
}
