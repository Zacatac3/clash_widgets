import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGettingStartedCardExistsAndShowsSteps() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the onboarding card to appear
        let card = app.otherElements["onboarding.getting_started_card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Getting Started card should appear on initial setup page")

        // Verify the three step lines are present
        let step1 = "1. Open the Clash of Clans Settings (or use the \"Open Game Settings\" button)"
        let step2 = "2. Within 'More Settings', scroll to the bottom and press the \"Copy\" button inside 'Data Export'"
        let step3 = "3. Press the Paste & Import Village Data button below"

        XCTAssertTrue(card.staticTexts[step1].exists, "Step 1 text should be visible")
        XCTAssertTrue(card.staticTexts[step2].exists, "Step 2 text should be visible")
        XCTAssertTrue(card.staticTexts[step3].exists, "Step 3 text should be visible")
    }
}
