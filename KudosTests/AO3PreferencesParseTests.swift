import Foundation
import Testing
@testable import Kudos

struct AO3PreferencesParseTests {
    @Test func parsesTogglesSelectsTextAndWebLinks() throws {
        let html = try fixture("ao3_preferences")
        let form = try AO3Client.parsePreferencesForm(from: html)

        #expect(form.actionURL.path == "/users/ExampleUser/preference")
        #expect(form.httpMethodOverride == "put")
        #expect(form.csrfToken == "csrf-token-abc123==")

        let toggles = form.allToggles
        #expect(toggles.contains(where: {
            $0.key == "disable_share_links" && $0.isOn
                && $0.label.contains("share buttons")
        }))
        #expect(toggles.contains(where: {
            $0.key == "minimize_search_engines" && !$0.isOn
        }))
        #expect(toggles.contains(where: {
            $0.key == "adult" && $0.isOn
        }))
        #expect(toggles.contains(where: {
            $0.key == "kudos_emails_off" && $0.isOn
        }))

        #expect(form.sections.map(\.title).contains("Privacy"))
        #expect(form.sections.map(\.title).contains("Display"))
        #expect(form.sections.map(\.title).contains("Comments"))

        // Section titles must not keep the literal "?" from the help control.
        #expect(!form.sections.map(\.title).contains(where: { $0.contains("?") }))

        let privacy = try #require(form.sections.first(where: { $0.title == "Privacy" }))
        #expect(privacy.help?.url.path == "/help/preferences_privacy")
        #expect(privacy.help?.title == "Privacy Preferences")

        let display = try #require(form.sections.first(where: { $0.title == "Display" }))
        #expect(display.help?.url.path == "/help/preferences_display")

        let skin = try #require(form.selects.first(where: { $0.key == "skin_id" }))
        #expect(skin.selectedValue == "42")
        #expect(skin.options.contains(where: { $0.title == "Reversi" && $0.value == "42" }))

        let zone = try #require(form.selects.first(where: { $0.key == "time_zone" }))
        #expect(zone.selectedValue == "America/New_York")

        let titleFormat = try #require(form.textFields.first(where: { $0.key == "work_title_format" }))
        #expect(titleFormat.value == "TITLE - AUTHOR")
        #expect(titleFormat.help?.url.path == "/help/preferences_work_title_format")
        #expect(titleFormat.help?.title == "Work Title Format")

        #expect(form.webLinks.contains(where: { $0.title == "Change Password" }))
        #expect(!form.webLinks.contains(where: { $0.url.path.contains("preferences") }))

        let params = Dictionary(uniqueKeysWithValues: form.preferenceParameters())
        #expect(params["preference[disable_share_links]"] == "1")
        #expect(params["preference[minimize_search_engines]"] == "0")
        #expect(params["preference[skin_id]"] == "42")
        #expect(params["preference[work_title_format]"] == "TITLE - AUTHOR")
        // Server hidden fields (not checkbox companions) ride along on save.
        #expect(params["preference[id]"] == "99")
        #expect(form.hiddenFields.contains(where: { $0.name == "preference[id]" && $0.value == "99" }))
    }

    @Test func parsesHelpPageBodyFromDefinitionList() throws {
        let html = try fixture("ao3_help_preferences_privacy")
        let url = try #require(URL(string: "https://archiveofourown.org/help/preferences_privacy"))
        let help = try AO3Client.parseHelpPage(from: html, sourceURL: url)

        #expect(help.title == "Privacy Preferences")
        #expect(help.entries.count == 3)
        #expect(help.entries[0].heading == "Hide my work from search engines when possible.")
        #expect(help.entries[0].body.contains("search engines not to index"))
        #expect(help.entries[1].body.contains("one-click share buttons"))
        #expect(help.footer?.contains("Preferences FAQ") == true)
        #expect(help.body.contains("Preferences FAQ"))
    }

    @Test func missingFormThrowsParseError() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parsePreferencesForm(from: "<html><body>no form</body></html>")
        }
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class BundleAnchor {}
