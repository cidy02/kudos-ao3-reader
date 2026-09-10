import Foundation
import Testing
@testable import Kudos

struct AO3ChallengeParsingTests {

    @Test func utcDateRoundTripDoesNotDrift() throws {
        let raw = "2026-12-31 23:59:00"
        let parsed = try #require(AO3ChallengeUTCDate.parse(raw))
        let wire = AO3ChallengeUTCDate.wireString(from: parsed)
        #expect(wire == "2026-12-31 23:59:00")
        let again = try #require(AO3ChallengeUTCDate.parse(wire))
        #expect(again == parsed)

        let iso = "2026-07-01T15:30:00Z"
        let fromISO = try #require(AO3ChallengeUTCDate.parse(iso))
        #expect(AO3ChallengeUTCDate.iso8601String(from: fromISO) == "2026-07-01T15:30:00Z")

        // Device timezone must not participate in the wire formatter.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        #expect(components.year == 2026)
        #expect(components.month == 12)
        #expect(components.day == 31)
        #expect(components.hour == 23)
        #expect(components.minute == 59)
        #expect(components.second == 0)

        let instant = AO3ChallengeInstant.parse("2026-01-15 12:00:00 UTC", timeZoneName: "UTC")
        #expect(instant.date != nil)
        #expect(instant.postedString == "2026-01-15 12:00:00")
    }

    @Test func signUpJoinsAssignmentMatchedState() throws {
        let signUpHTML = """
        <html><body>
        <h2 class="heading">Sign-ups for Winter Fest</h2>
        <ul class="index group">
          <li class="challenge signup blurb" id="signup_11">
            <h4 class="heading"><a href="/collections/fest/signups/11">Alice</a></h4>
            <a class="tag">Star Wars</a>
          </li>
          <li class="challenge signup blurb" id="signup_12">
            <h4 class="heading"><a href="/collections/fest/signups/12">Bob</a></h4>
            <a class="tag">Trek</a>
          </li>
        </ul>
        </body></html>
        """
        let assignmentHTML = """
        <html><body>
        <h2 class="heading">Assignments for Winter Fest</h2>
        <ul>
          <li class="assignment" id="assignment_80">
            <a href="/collections/fest/assignments/80">Alice</a>
            <span class="request">Alice</span>
            <span class="offer">Carol</span>
          </li>
        </ul>
        </body></html>
        """
        let signUps = try AO3Client.parseChallengeSignUpsPage(signUpHTML, slug: "fest", page: 1)
        let assignments = try AO3Client.parseChallengeAssignmentsPage(
            assignmentHTML, slug: "fest", page: 1
        )
        let joined = AO3ChallengeSignUpMatching.joining(
            signUps.signUps, assignments: assignments.assignments
        )
        let alice = try #require(joined.first(where: { $0.pseud == "Alice" }))
        let bob = try #require(joined.first(where: { $0.pseud == "Bob" }))
        #expect(alice.isMatched)
        #expect(alice.assignment?.id == 80)
        #expect(alice.assignment?.offerPseud == "Carol")
        #expect(!bob.isMatched)
        #expect(bob.assignment == nil)
    }

    @Test func challengeSettingsParseFiveUTCDatesAndMatchingURL() throws {
        let html = """
        <html>
        <head><meta name="csrf-token" content="csrf-challenge"></head>
        <body>
        <form action="/collections/fest/gift_exchange" method="post">
          <input type="hidden" name="_method" value="put">
          <input type="hidden" name="authenticity_token" value="csrf-challenge">
          <input type="checkbox" name="gift_exchange[signup_open]" value="1" checked>
          <select name="gift_exchange[time_zone]"><option value="UTC" selected>UTC</option></select>
          <input name="gift_exchange[signups_open_at_string]" value="2026-01-01 00:00:00">
          <input name="gift_exchange[signups_close_at_string]" value="2026-02-01 00:00:00">
          <input name="gift_exchange[assignments_due_at_string]" value="2026-03-01 00:00:00">
          <input name="gift_exchange[works_reveal_at_string]" value="2026-04-01 00:00:00">
          <input name="gift_exchange[authors_reveal_at_string]" value="2026-05-01 00:00:00">
          <input name="gift_exchange[requests_num_required]" value="1">
          <input name="gift_exchange[requests_num_allowed]" value="3">
          <input name="gift_exchange[offers_num_required]" value="1">
          <input name="gift_exchange[offers_num_allowed]" value="2">
        </form>
        </body></html>
        """
        let form = try AO3Client.parseChallengeSettingsForm(html, slug: "fest", kind: .giftExchange)
        #expect(form.settings.kind == .giftExchange)
        #expect(form.settings.signupOpen)
        #expect(form.settings.signupsOpenAt.postedString == "2026-01-01 00:00:00")
        #expect(form.settings.signupsCloseAt.postedString == "2026-02-01 00:00:00")
        #expect(form.settings.assignmentsDueAt.postedString == "2026-03-01 00:00:00")
        #expect(form.settings.worksRevealAt.postedString == "2026-04-01 00:00:00")
        #expect(form.settings.authorsRevealAt.postedString == "2026-05-01 00:00:00")
        #expect(form.settings.limits.requestsAllowed == 3)
        #expect(form.settings.matchingOpenOnAO3.path == "/collections/fest/potential_matches")
        // Matching is Open on AO3 — there is no runMatching() write on AO3AuthService.
        let params = Dictionary(uniqueKeysWithValues: AO3Client.challengeSettingsParameters(form))
        #expect(params["gift_exchange[time_zone]"] == "UTC")
        #expect(params["gift_exchange[signups_open_at_string]"] == "2026-01-01 00:00:00")

        var inverted = form
        inverted.settings.signupsCloseAt = AO3ChallengeInstant.parse("2025-01-01 00:00:00")
        let invalid = inverted.validated()
        #expect(!invalid.isValid)
        #expect(invalid.fieldErrors["signups_close_at"] != nil)
    }

    @Test func promptMemeAnonymousHidesOwnerEvenIfPresent() throws {
        let html = """
        <html><body>
        <h2 class="heading">Prompts</h2>
        <ul class="index group">
          <li class="prompt blurb anonymous" id="prompt_5">
            <h4 class="heading"><a href="/users/hiddenowner">HiddenOwner</a></h4>
            <blockquote class="userstuff">A quiet prompt.</blockquote>
            <a class="tag">Fandom</a>
          </li>
        </ul>
        </body></html>
        """
        let page = try AO3Client.parsePromptMemePage(html, slug: "meme", page: 1)
        let prompt = try #require(page.prompts.first)
        #expect(prompt.isAnonymous)
        #expect(prompt.displayedOwner == nil)
        #expect(prompt.promptText.contains("quiet prompt"))
    }

    @Test func tagSetFourFieldsAndAssociationURLHaveNoWrite() throws {
        let html = """
        <html>
        <head><meta name="csrf-token" content="csrf-tags"></head>
        <body>
        <h2 class="heading">Exchange Tags</h2>
        <form action="/tag_sets/9" method="post">
          <input type="hidden" name="_method" value="put">
          <input name="owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]" value="SW, Trek">
          <input name="owned_tag_set[tag_set_attributes][character_tagnames_to_add]" value="Leia">
          <input name="owned_tag_set[tag_set_attributes][relationship_tagnames_to_add]" value="Leia/Han">
          <input name="owned_tag_set[tag_set_attributes][freeform_tagnames_to_add]" value="Hurt/Comfort">
          <input name="owned_tag_set[fandom_nomination_limit]" value="2">
          <input name="owned_tag_set[character_nomination_limit]" value="3">
          <input name="owned_tag_set[relationship_nomination_limit]" value="3">
          <input name="owned_tag_set[freeform_nomination_limit]" value="5">
        </form>
        <ul>
          <li class="nomination">fandom unreviewed Star Wars</li>
          <li class="nomination">character approved Leia Organa</li>
          <li class="nomination">freeform rejected Crack</li>
        </ul>
        </body></html>
        """
        let tagSet = try AO3Client.parseTagSet(html, id: 9)
        #expect(tagSet.fandomTagnames == "SW, Trek")
        #expect(tagSet.characterTagnames == "Leia")
        #expect(tagSet.relationshipTagnames == "Leia/Han")
        #expect(tagSet.freeformTagnames == "Hurt/Comfort")
        #expect(tagSet.fandomNominationLimit == 2)
        #expect(tagSet.associationOpenOnAO3.path == "/tag_sets/9/associations")
        let nominations = try AO3Client.parseTagSetNominations(html)
        #expect(nominations.contains(where: { $0.state == .unreviewed && $0.field == .fandom }))
        #expect(nominations.contains(where: { $0.state == .approved && $0.field == .character }))
        #expect(nominations.contains(where: { $0.state == .rejected && $0.field == .freeform }))
        let reject = AO3Client.rejectedTagParam(field: .fandom, tagName: "Star Wars")
        #expect(reject.0 == "fandom_reject_Star Wars")
        #expect(reject.1 == "1")
        // Association is Open on AO3 — there is no associateTagSet() write.
    }

    @Test func ownSignUpParsesNestedRequestsAndOffers() throws {
        let html = """
        <html>
        <head><meta name="csrf-token" content="csrf-signup"></head>
        <body>
        <form action="/collections/fest/signups/4" method="post">
          <input type="hidden" name="_method" value="put">
          <input name="challenge_signup[pseud_id]" type="hidden" value="15">
          <input name="challenge_signup[requests_attributes][0][id]" value="21">
          <input name="challenge_signup[requests_attributes][0][tag_set_attributes][fandom_tagnames]" value="Star Wars">
          <textarea name="challenge_signup[requests_attributes][0][description]">A request</textarea>
          <input name="challenge_signup[offers_attributes][0][id]" value="22">
          <input name="challenge_signup[offers_attributes][0][tag_set_attributes][fandom_tagnames]" value="Trek">
        </form>
        </body></html>
        """
        let form = try AO3Client.parseChallengeSignUpForm(html, slug: "fest")
        #expect(form.signUpID == 4)
        #expect(form.pseudID == "15")
        #expect(form.requests.count == 1)
        #expect(form.requests[0].fandoms == ["Star Wars"])
        #expect(form.offers.count == 1)
        #expect(form.offers[0].fandoms == ["Trek"])
    }
}
