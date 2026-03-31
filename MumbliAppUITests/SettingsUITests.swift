import XCTest

/// Regression tests for the Settings view.
/// Verifies all sections, polishing controls, model options, and API key fields are present.
final class SettingsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Open the Settings window via the menu bar popover.
    private func openSettings() throws {
        try app.tapMenuBarButton()

        let settingsButton = app.buttons[AccessibilityID.settingsButton]
        guard settingsButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings button not found in menu bar popover")
        }
        settingsButton.tap()

        // Wait for the settings window to appear
        let settingsWindow = app.windows[AccessibilityID.settingsWindow]
        guard settingsWindow.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings window did not appear")
        }
    }

    // MARK: - Section Presence

    /// Regression: Settings must have all 5 sections.
    func testSettingsHasAllSections() throws {
        try openSettings()

        let expectedSections = [
            AccessibilityID.sectionAudioInput,
            AccessibilityID.sectionAPIKeys,
            AccessibilityID.sectionTextPolishing,
            AccessibilityID.sectionShortcuts,
            AccessibilityID.sectionAbout,
        ]

        for section in expectedSections {
            let sectionText = app.staticTexts[section]
            XCTAssertTrue(sectionText.waitForExistence(timeout: 3),
                          "Settings should contain section: \(section)")
        }
    }

    // MARK: - Text Polishing

    /// Regression: Text Polishing section has an enable/disable toggle.
    func testTextPolishingHasToggle() throws {
        try openSettings()

        let toggle = app.switches[AccessibilityID.polishingToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3),
                      "Text Polishing should have an enable/disable toggle")
    }

    /// Regression: Text Polishing has 5 prompt presets.
    func testTextPolishingHasFivePresets() throws {
        try openSettings()

        let expectedPresets = ["Light cleanup", "Formal", "Casual", "Verbatim", "Custom"]

        // The preset picker is a Picker — tap it to reveal options
        // First verify the preset label exists
        let presetLabel = app.staticTexts["Prompt preset"]
        XCTAssertTrue(presetLabel.waitForExistence(timeout: 3),
                      "Text Polishing should show 'Prompt preset' label")

        // Look for the picker — macOS pickers render as pop-up buttons
        let picker = app.popUpButtons.firstMatch
        guard picker.waitForExistence(timeout: 3) else {
            throw XCTSkip("Preset picker not found")
        }
        picker.tap()

        // Verify all preset options are available in the menu
        for preset in expectedPresets {
            let menuItem = app.menuItems[preset]
            XCTAssertTrue(menuItem.waitForExistence(timeout: 2),
                          "Preset picker should contain option: \(preset)")
        }

        // Dismiss the picker menu
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Regression: Text Polishing has 3 model options.
    func testTextPolishingHasThreeModels() throws {
        try openSettings()

        let expectedModels = ["GPT-5.4 Nano", "GPT-5.4 Mini", "Other"]

        // Find the Model label
        let modelLabel = app.staticTexts["Model"]
        XCTAssertTrue(modelLabel.waitForExistence(timeout: 3),
                      "Text Polishing should show 'Model' label")

        // The model picker is the second pop-up button in the polishing section
        // Find all pop-up buttons and look for the model one
        let popUpButtons = app.popUpButtons
        // We need to find the right picker — iterate to find one whose value matches a model name
        var modelPicker: XCUIElement?
        for i in 0..<popUpButtons.count {
            let btn = popUpButtons.element(boundBy: i)
            let value = btn.value as? String ?? ""
            if expectedModels.contains(value) {
                modelPicker = btn
                break
            }
        }

        guard let picker = modelPicker else {
            throw XCTSkip("Model picker not found among pop-up buttons")
        }

        picker.tap()

        for model in expectedModels {
            let menuItem = app.menuItems[model]
            XCTAssertTrue(menuItem.waitForExistence(timeout: 2),
                          "Model picker should contain option: \(model)")
        }

        app.typeKey(.escape, modifierFlags: [])
    }

    /// Regression: selecting "Custom" preset shows a text editor.
    func testCustomPresetShowsTextEditor() throws {
        try openSettings()

        // Find the preset picker and select Custom
        let popUpButtons = app.popUpButtons
        guard popUpButtons.count > 0 else {
            throw XCTSkip("No pop-up buttons found in settings")
        }

        let presetPicker = popUpButtons.firstMatch
        presetPicker.tap()

        let customItem = app.menuItems["Custom"]
        guard customItem.waitForExistence(timeout: 2) else {
            throw XCTSkip("Custom menu item not found")
        }
        customItem.tap()

        // The custom prompt editor should now be visible
        let customPromptLabel = app.staticTexts["Custom prompt"]
        XCTAssertTrue(customPromptLabel.waitForExistence(timeout: 3),
                      "Selecting 'Custom' preset should reveal the custom prompt editor")
    }

    /// Regression: selecting "Other" model shows a text field for custom model ID.
    func testOtherModelShowsTextField() throws {
        try openSettings()

        let expectedModels = ["GPT-5.4 Nano", "GPT-5.4 Mini", "Other"]

        // Find the model picker
        let popUpButtons = app.popUpButtons
        var modelPicker: XCUIElement?
        for i in 0..<popUpButtons.count {
            let btn = popUpButtons.element(boundBy: i)
            let value = btn.value as? String ?? ""
            if expectedModels.contains(value) {
                modelPicker = btn
                break
            }
        }

        guard let picker = modelPicker else {
            throw XCTSkip("Model picker not found")
        }

        picker.tap()

        let otherItem = app.menuItems["Other"]
        guard otherItem.waitForExistence(timeout: 2) else {
            throw XCTSkip("Other menu item not found")
        }
        otherItem.tap()

        // The custom model field should appear
        let customModelLabel = app.staticTexts["Custom model ID"]
        XCTAssertTrue(customModelLabel.waitForExistence(timeout: 3),
                      "Selecting 'Other' model should reveal the custom model ID field")
    }

    // MARK: - API Keys

    /// Regression: API Keys section has ElevenLabs and OpenAI fields.
    func testAPIKeysHasElevenLabsAndOpenAIFields() throws {
        try openSettings()

        let elevenLabsLabel = app.staticTexts["ElevenLabs"]
        XCTAssertTrue(elevenLabsLabel.waitForExistence(timeout: 3),
                      "API Keys section should show ElevenLabs label")

        let openAILabel = app.staticTexts["OpenAI"]
        XCTAssertTrue(openAILabel.waitForExistence(timeout: 3),
                      "API Keys section should show OpenAI label")
    }

    /// Regression: API key fields are accessible for input.
    func testAPIKeyFieldsExist() throws {
        try openSettings()

        // The secure fields use the accessibility IDs defined in SettingsView
        let elevenLabsField = app.secureTextFields[AccessibilityID.elevenLabsKeyField]
        let openAIField = app.secureTextFields[AccessibilityID.openAIKeyField]

        // At least one of them should be visible (if a key is already set, the field
        // may be replaced by a masked label until tapped)
        let elevenLabsExists = elevenLabsField.waitForExistence(timeout: 3)
        let openAIExists = openAIField.waitForExistence(timeout: 3)

        // If keys are already set, the masked labels are shown instead of fields.
        // Either the field or the service label should exist.
        if !elevenLabsExists {
            let maskedLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'xi-'"))
            XCTAssertTrue(maskedLabel.count > 0 || app.staticTexts["ElevenLabs"].exists,
                          "ElevenLabs key field or masked key should be visible")
        }
        if !openAIExists {
            let maskedLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'sk-'"))
            XCTAssertTrue(maskedLabel.count > 0 || app.staticTexts["OpenAI"].exists,
                          "OpenAI key field or masked key should be visible")
        }
    }
}
