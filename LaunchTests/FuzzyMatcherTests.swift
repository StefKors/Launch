import Testing
@testable import Launch

struct FuzzyMatcherTests {
    private func score(_ query: String, _ name: String) -> Double? {
        FuzzyMatcher.score(query, in: name)
    }

    @Test func tiersRankInOrder() throws {
        let exact = try #require(score("safari", "Safari"))
        let prefix = try #require(score("saf", "Safari"))
        let wordPrefix = try #require(score("code", "Visual Studio Code"))
        let initials = try #require(score("vsc", "Visual Studio Code"))
        let substring = try #require(score("tudi", "Visual Studio Code"))
        let subsequence = try #require(score("vsdc", "Visual Studio Code"))
        #expect(exact > prefix)
        #expect(prefix > wordPrefix)
        #expect(wordPrefix > initials)
        #expect(initials > substring)
        #expect(substring > subsequence)
    }

    @Test func shorterNameWinsAmongPrefixes() throws {
        let short = try #require(score("ter", "Terminal"))
        let long = try #require(score("ter", "Terminus Extended Reader"))
        #expect(short > long)
    }

    @Test func initialsFindMultiWordNames() {
        #expect(score("sysset", "System Settings") != nil)
        #expect(score("ss", "System Settings") != nil)
        #expect(score("tm", "Time Machine") != nil)
    }

    @Test func camelCaseWordsCount() {
        #expect(score("time", "QuickTime Player") != nil)
        #expect(score("qtp", "QuickTime Player") != nil)
    }

    @Test func multipleTermsMatchWordsInOrder() {
        #expect(score("visual code", "Visual Studio Code") != nil)
        #expect(score("code visual", "Visual Studio Code") == nil)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(score("CAFE", "Café") != nil)
        #expect(score("cafe", "Café") == score("café", "Café"))
    }

    @Test func rejectsNonMatchesAndEmptyQueries() {
        #expect(score("xyz", "Safari") == nil)
        #expect(score("", "Safari") == nil)
        #expect(score("   ", "Safari") == nil)
        // Characters must appear in order.
        #expect(score("ifas", "Safari") == nil)
    }
}
