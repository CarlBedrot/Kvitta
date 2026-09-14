import Testing
@testable import Kvitta

/// The emoji a row gets is read off its description, since nobody picks a category any more.
struct CategoryInferenceTests {
    @Test func shopNamesAndMealsMapToTheirCategory() {
        #expect(Categories.infer(from: "ICA") == "groceries")
        #expect(Categories.infer(from: "Systembolaget") == "alkohol")
        #expect(Categories.infer(from: "Middag i København") == "restaurang")
        #expect(Categories.infer(from: "Taxi hem") == "taxi")
        #expect(Categories.infer(from: "Airbnb Berlin") == "boende")
    }

    @Test func matchingIgnoresCase() {
        #expect(Categories.infer(from: "fika på Espresso House") == "fika")
        #expect(Categories.infer(from: "PADEL") == "sport")
    }

    @Test func unknownTextFallsBackToÖvrigt() {
        #expect(Categories.infer(from: "Present till Sara") == Categories.fallbackId)
        #expect(Categories.infer(from: "") == Categories.fallbackId)
    }
}
