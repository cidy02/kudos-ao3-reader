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
        #expect(instant.wallClock != nil)
        #expect(instant.postedString == "2026-01-15 12:00:00")
    }

    /// otwarchive's schedule fieldset (Q4): the `*_at_string` inputs are wall
    /// clocks in `gift_exchange[time_zone]`; works_reveal_at_string is rendered
    /// only for an unrevealed collection and authors_reveal_at_string only for an
    /// anonymous one, so this revealed, non-anonymous challenge has neither.
    @Test func challengeDatesStayInTheChallengesOwnZone() throws {
        func form(zone: String) throws -> AO3ChallengeSettingsForm {
            try AO3Client.parseChallengeSettingsForm("""
            <form action="/collections/fest/gift_exchange" method="post">
              <input type="hidden" name="_method" value="put">
              <input type="hidden" name="authenticity_token" value="csrf">
              <input name="gift_exchange[signups_open_at_string]" value="2026-01-01 09:00:00">
              <input name="gift_exchange[signups_close_at_string]" value="2026-02-01 23:59:00">
              <input name="gift_exchange[assignments_due_at_string]" value="2026-03-01 23:59:00">
              <select name="gift_exchange[time_zone]"><option value="UTC">UTC</option>
                <option value="\(zone)" selected="selected">\(zone)</option></select>
            </form>
            """, slug: "fest", kind: .giftExchange)
        }
        let eastern = try form(zone: "America/New_York").settings
        // 23:59 on 1 March in New York is 04:59 UTC on 2 March.
        let due = try #require(eastern.worksDueAt.instant)
        #expect(due == Date(timeIntervalSince1970: 1_772_427_540))
        let open = AO3ChallengeAssignment(id: 1, collectionSlug: "fest", offerPseud: "Giver")
        #expect(open.badge(dueAt: due, now: Date(timeIntervalSince1970: 1_772_427_540 - 3600)) == nil)
        #expect(open.badge(dueAt: due, now: Date(timeIntervalSince1970: 1_772_427_540 + 60)) == .late)

        let params = Dictionary(uniqueKeysWithValues: AO3Client.challengeSettingsParameters(
            try form(zone: "America/New_York")
        ))
        #expect(params["gift_exchange[time_zone]"] == "America/New_York")
        #expect(params["gift_exchange[assignments_due_at_string]"] == "2026-03-01 23:59:00")
        #expect(params["gift_exchange[works_reveal_at_string]"] == nil)
        #expect(params["gift_exchange[authors_reveal_at_string]"] == nil)
        #expect(!eastern.worksRevealAt.isOnForm && eastern.worksRevealAt.dateText == nil)

        // A Rails zone name Foundation cannot resolve: the digits and zone still
        // round-trip, and no moment is claimed.
        let rails = try form(zone: "Eastern Time (US &amp; Canada)")
        #expect(rails.settings.worksDueAt.instant == nil)
        let railsParams = Dictionary(uniqueKeysWithValues: AO3Client.challengeSettingsParameters(rails))
        #expect(railsParams["gift_exchange[time_zone]"] == "Eastern Time (US & Canada)")
        #expect(railsParams["gift_exchange[assignments_due_at_string]"] == "2026-03-01 23:59:00")
    }

    /// Rendered shape of otwarchive's gift_exchange/_challenge_signups with
    /// challenge_signups/_show_requests, _show_offers and prompts/_prompt_blurb
    /// (master 00ad85b4): a dt.participant byline per sign-up, then a dd whose
    /// div#requests_<id> / div#offers_<id> hold one li.blurb per prompt, each div
    /// omitted when its list is empty. Not a production capture: the index is
    /// maintainer-only.
    static let signUpIndexHTML = """
    <html><body>
    <h2 class="heading">Sign-ups for Winter Fest</h2>
    <dl class="index group">
      <dt class="participant"><a href="/collections/fest/signups/11">Alice</a>
        <a class="mailto" href="mailto:alice@example.test"><img alt="email alice"></a></dt>
      <dd>
        <ul class="actions"><li><a href="/collections/fest/signups/11/edit">Edit Sign-up</a></li>
          <li><a href="/collections/fest/signups/11/confirm_delete">Delete Sign-up</a></li></ul>
        <ul class="actions"><li><a href="#">Requests ↓</a></li><li><a href="#">Offers ↓</a></li></ul>
        <div class="toggled" id="requests_11"><div class="requests listbox group"><ol class="prompt index group">
          <li class="request blurb group" role="article">
            <h4 class="heading">Request 1 by Alice</h4>
            <h5 class="fandoms heading"><a class="tag" href="/tags/Good%20Omens%20(TV)">Good Omens (TV)</a></h5>
            <ul class="tags commas">
              <li class="relationships"><a class="tag" href="/tags/x">Aziraphale/Crowley</a></li>
              <li class="freeforms"><a class="tag" href="/tags/y">Slow Burn</a></li>
            </ul>
            <ul class="optional tags commas"><li class="freeforms"><a class="tag" href="/tags/z">Fluff</a></li></ul>
            <blockquote class="userstuff summary"><p>A bookshop that rearranges itself.</p></blockquote>
          </li>
          <li class="request blurb group" role="article">
            <h4 class="heading">Request 2 by Alice</h4>
            <h5 class="fandoms heading"><a class="tag" href="/tags/n">Naruto</a>
              <a class="tag" href="/tags/Good%20Omens%20(TV)">Good Omens (TV)</a></h5>
          </li>
        </ol></div></div>
        <div class="toggled" id="offers_11"><div class="offers listbox group"><ol class="prompt index group">
          <li class="offer blurb group" role="article">
            <h4 class="heading">Offer 1 by Alice</h4>
            <h5 class="fandoms heading"><a class="tag" href="/tags/sw">Star Wars</a></h5>
          </li>
        </ol></div></div>
      </dd>
      <dt class="participant"><a href="/collections/fest/signups/12">Bob (bobby)</a>
        <a class="mailto" href="mailto:bob@example.test"><img alt="email bobby"></a></dt>
      <dd>
        <ul class="actions"><li><a href="/collections/fest/signups/12/edit">Edit Sign-up</a></li></ul>
        <div class="toggled" id="requests_12"><div class="requests listbox group"><ol class="prompt index group">
          <li class="request blurb group" role="article">
            <h4 class="heading">Request 1 by Anonymous</h4>
            <ul class="tags commas"><li class="tag">Any Fandom</li>
              <li class="characters"><a class="tag" href="/tags/k">Kirk</a></li></ul>
            <ul class="optional tags commas"><li class="freeforms"><a class="tag" href="/tags/z">Fluff</a></li></ul>
          </li>
        </ol></div></div>
      </dd>
    </dl>
    <ol class="pagination actions"><li><span class="current">1</span></li>
      <li><a href="/collections/fest/signups?page=2">2</a></li></ol>
    </body></html>
    """

    @Test func signUpIndexCountsEachRowsRequestsAndOffers() throws {
        let page = try AO3Client.parseChallengeSignUpsPage(Self.signUpIndexHTML, slug: "fest", page: 1)
        try #require(page.signUps.map(\.id) == [11, 12])
        #expect(page.totalPages == 2)
        let alice = page.signUps[0]
        #expect(alice.pseud == "Alice")
        try #require(alice.requests.count == 2)
        try #require(alice.offers.count == 1)
        #expect(alice.requests[0].relationships == ["Aziraphale/Crowley"])
        // The optional-tags list is not a chosen tag, but it is kept apart.
        #expect(alice.requests[0].freeforms == ["Slow Burn"])
        #expect(alice.requests[0].optionalTags == ["Fluff"])
        #expect(alice.requests[0].promptText == "A bookshop that rearranges itself.")
        #expect(alice.offers[0].fandoms == ["Star Wars"])
        // Distinct request fandoms, in order: 1bz's one-line summary.
        #expect(alice.requestTagSummary == "Good Omens (TV), Naruto")
        let bob = page.signUps[1]
        #expect(bob.pseud == "Bob (bobby)")
        try #require(bob.requests.count == 1)
        #expect(bob.offers.isEmpty)
        // "Any Fandom" is a bare li.tag with no link; the request is not empty.
        #expect(bob.requests[0].anyFandom)
        #expect(!bob.requests[0].anyCharacter)
        #expect(bob.requests[0].characters == ["Kirk"])
        #expect(bob.requests[0].optionalTags == ["Fluff"])
        #expect(bob.requestTagSummary == "Any Fandom")
        // A prompt meme's index prints the heading and no rows.
        let meme = try AO3Client.parseChallengeSignUpsPage(
            "<h2 class='heading'>Sign-ups for Meme</h2>", slug: "meme", page: 1
        )
        #expect(meme.signUps.isEmpty)
    }

    @Test func signUpJoinsAssignmentMatchedState() throws {
        let signUpHTML = Self.signUpIndexHTML
        // Rendered shape of maintainer_index_unfulfilled.html.erb, not a
        // production capture: assignment indexes require collection-maintainer access.
        let assignmentHTML = """
        <html><body><h2 class="heading">Assignments for Winter Fest</h2>
        <dl class="index group">
          <dt class="creator">Carol <a href="mailto:carol@example.test">Email</a>
            <span class="recipient">for <a href="/collections/fest/signups/11">Alice</a></span>
          </dt>
          <dd>Not yet posted<ul class="actions"><li><label for="default_80">Default
            <input name="default_80" type="checkbox" value="1"></label></li></ul></dd>
        </dl></body></html>
        """
        let signUps = try AO3Client.parseChallengeSignUpsPage(signUpHTML, slug: "fest", page: 1)
        let assignments = try AO3Client.parseChallengeAssignmentsPage(
            assignmentHTML, slug: "fest", page: 1
        )
        let joined = AO3ChallengeSignUpMatching.joining(
            signUps.signUps, assignments: assignments.assignments
        )
        let alice = try #require(joined.first(where: { $0.pseud == "Alice" }))
        let bob = try #require(joined.first(where: { $0.pseud == "Bob (bobby)" }))
        #expect(alice.isMatched)
        #expect(alice.assignment?.id == 80)
        #expect(alice.assignment?.offerPseud == "Carol")
        #expect(alice.assignment?.requestSignupID == 11)
        #expect(alice.assignment?.isFulfilled == false)
        #expect(alice.assignment?.isDefaulted == false)
        #expect(!bob.isMatched)
        #expect(bob.assignment == nil)
    }

    @Test func signUpMatchStateIsUnknownWithoutAssignments() {
        let alice = AO3ChallengeSignUp(id: 11, collectionSlug: "fest", pseud: "Alice")
        let carol = AO3ChallengeAssignment(id: 80, collectionSlug: "fest", offerPseud: "Carol")
        // A failed assignments fetch must not read as "unmatched".
        #expect(AO3ChallengeSignUpMatching.state(of: alice, assignments: nil) == .unknown)
        #expect(AO3ChallengeSignUpMatching.state(of: alice, assignments: [carol]) == .unmatched)
        var matched = alice
        matched.assignment = carol
        #expect(AO3ChallengeSignUpMatching.state(of: matched, assignments: nil) == .unknown)
        #expect(AO3ChallengeSignUpMatching.state(of: matched, assignments: [carol]) == .matched)
        // A defaulted, uncovered giver is what 1cb lists as unmatched.
        matched.assignment?.isDefaulted = true
        #expect(AO3ChallengeSignUpMatching.state(of: matched, assignments: [carol]) == .unmatched)
    }

    /// Before send-out every list is AO3's empty "No assignments" page, which
    /// parses fine: three empty lists are no assignments, not three unmatched.
    @Test func emptyAssignmentListsLeaveMatchStateUnknown() async throws {
        let empty = """
        <h2 class="heading">Assignments for Winter Fest</h2><p class="note">No assignments to review!</p>
        """
        let assignments = try await AO3Client.allChallengeAssignments { _, page in
            try AO3Client.parseChallengeAssignmentsPage(empty, slug: "fest", page: page)
        }
        #expect(assignments.isEmpty)
        let alice = AO3ChallengeSignUp(id: 11, collectionSlug: "fest", pseud: "Alice")
        #expect(AO3ChallengeSignUpMatching.state(of: alice, assignments: assignments) == .unknown)
    }

    @Test func failedLoadMoreKeepsRowsAndRetriesThePage() async throws {
        struct Offline: Error {}
        var pager = AO3LoadMorePages<Int>()
        try await pager.loadNext { page in ([page * 10], 3) }
        await #expect(throws: Offline.self) {
            try await pager.loadNext { _ in throw Offline() }
        }
        // Page 2 failed: page 1's rows stay, and Load more still offers page 2.
        #expect(pager.rows == [10])
        #expect(pager.loadedPages == 1)
        #expect(pager.hasMore)
        var asked: [Int] = []
        try await pager.loadNext { page in asked.append(page); return ([page * 10], 3) }
        try await pager.loadNext { page in asked.append(page); return ([page * 10], 3) }
        #expect(asked == [2, 3])
        #expect(pager.rows == [10, 20, 30])
        #expect(!pager.hasMore)
    }

    @Test func ownSignUpMatchesBylineOrPseudWithLogin() {
        let rows = [
            AO3ChallengeSignUp(id: 11, collectionSlug: "fest", pseud: "Alice"),
            AO3ChallengeSignUp(id: 12, collectionSlug: "fest", pseud: "Bob (bobby)")
        ]
        #expect(AO3ChallengeSignUpMatching.ownSignUpID(in: rows, login: "alice") == 11)
        #expect(AO3ChallengeSignUpMatching.ownSignUpID(in: rows, login: "bobby") == 12)
        #expect(AO3ChallengeSignUpMatching.ownSignUpID(in: rows, login: "bob") == nil)
        #expect(AO3ChallengeSignUpMatching.ownSignUpID(in: rows, login: "") == nil)
        #expect(AO3ChallengeSignUpMatching.owns(byline: "WriterName (alice)", login: "alice"))
        #expect(!AO3ChallengeSignUpMatching.owns(byline: "WriterName (bob)", login: "alice"))
    }

    @Test func assignmentBadgeDerivesLateFromWorksDue() {
        let due = Date(timeIntervalSince1970: 1_000_000)
        let before = due.addingTimeInterval(-60)
        let after = due.addingTimeInterval(60)
        let open = AO3ChallengeAssignment(id: 1, collectionSlug: "fest", offerPseud: "Giver")
        #expect(open.badge(dueAt: due, now: before) == nil)
        #expect(open.badge(dueAt: due, now: after) == .late)
        // No due date, no late claim.
        #expect(open.badge(dueAt: nil, now: after) == nil)
        var delivered = open
        delivered.isFulfilled = true
        #expect(delivered.badge(dueAt: due, now: after) == .delivered)
        var defaulted = open
        defaulted.isDefaulted = true
        #expect(defaulted.badge(dueAt: due, now: after) == .defaulted)
    }

    @Test func draftPromptIDsStayUniqueAndAreNeverPosted() throws {
        var form = AO3ChallengeSignUpForm(
            actionURL: try #require(URL(string: "https://archiveofourown.org/collections/fest/signups")),
            csrfToken: "csrf", collectionSlug: "fest", pseudID: "15",
            requests: [AO3ChallengePrompt(id: 21, kind: .request)], offers: []
        )
        // Seeding an offer then adding one used to give both id -2.
        form.offers.append(AO3ChallengePrompt(id: form.nextDraftPromptID, kind: .offer))
        form.offers.append(AO3ChallengePrompt(id: form.nextDraftPromptID, kind: .offer))
        form.requests.append(AO3ChallengePrompt(id: form.nextDraftPromptID, kind: .request))
        let ids = (form.requests + form.offers).map(\.id)
        #expect(Set(ids).count == ids.count)
        let posted = AO3Client.challengeSignUpParameters(form).filter { $0.0.hasSuffix("[id]") }
        #expect(posted.map(\.1) == ["21"])
    }

    @Test func signUpTotalReadsTheLastPageAndPageLabels() async throws {
        func page(_ number: Int, rows: Int, of total: Int) -> AO3ChallengeSignUpPage {
            AO3ChallengeSignUpPage(
                signUps: (0..<rows).map { AO3ChallengeSignUp(id: number * 100 + $0, collectionSlug: "fest", pseud: "p") },
                currentPage: number, totalPages: total
            )
        }
        // will_paginate: every page but the last is full, so only the last is read.
        var asked: [Int] = []
        let total = try await AO3Client.signUpTotal(firstPage: page(1, rows: 20, of: 3)) { number in
            asked.append(number)
            return page(number, rows: 7, of: 3)
        }
        #expect(asked == [3])
        #expect(total == 47)
        let single = try await AO3Client.signUpTotal(firstPage: page(1, rows: 5, of: 1)) { _ in
            Issue.record("A single page needs no second fetch")
            return page(1, rows: 5, of: 1)
        }
        #expect(single == 5)
        #expect(AO3ChallengeCountText.plural(1, "sign-up") == "1 sign-up")
        #expect(AO3ChallengeCountText.plural(31, "sign-up") == "31 sign-ups")
        #expect(AO3ChallengeCountText.pageQualifier(page: 2, totalPages: 4) == "on page 2 of 4")
        #expect(AO3ChallengeCountText.pageQualifier(page: 1, totalPages: 1) == nil)
    }

    @Test func assignmentTemplatesPreserveDefaultAndDeliveryStates() throws {
        // From _assignment_blurb, _maintainer_index_defaulted and
        // _maintainer_index_unfulfilled in otwcode/otwarchive (2026-09-12).
        let html = """
        <h2 class="heading">Assignments for Fest</h2>
        <dl class="index group">
          <dt>Giver <a href="mailto:giver@example.test">Email</a></dt>
          <dd><a class="work" href="/works/501">Gift</a> for
            <a href="/collections/fest/assignments/81">Recipient</a>
            <dl class="stats"><dt>Status:</dt><dd>Complete</dd></dl></dd>
          <dt class="assignment"><a href="/collections/fest/signups/12">Bob</a>
            <span class="defaulter">(Also defaulted)</span></dt>
          <dd><label for="undefault_82">Undefault FormerGiver
              <input name="undefault_82" type="checkbox"></label>
            <label class="autocomplete substitute">Pinch Hitter:
              <input name="cover_82"></label></dd>
          <dt class="creator">Replacement* (pinch hitter)
            <a href="mailto:replacement@example.test">Email</a>
            <span class="recipient">for <a href="/collections/fest/signups/13">Casey</a></span></dt>
          <dd>Not yet posted<ul class="actions"><li><label for="default_83">Default
            <input name="default_83" type="checkbox"></label></li></ul></dd>
          <dt class="creator"><span class="recipient">for <strong>No Recipient!</strong></span></dt>
          <dd><label for="default_84">Default<input name="default_84" type="checkbox"></label></dd>
        </dl>
        """
        let rows = try AO3Client.parseChallengeAssignmentsPage(html, slug: "fest", page: 1).assignments
        #expect(rows.map(\.id) == [81, 82, 83, 84])
        #expect(rows[0].requestSignupID == nil)
        #expect(rows[0].requestPseud == "Recipient")
        #expect(rows[0].offerPseud == "Giver")
        #expect(rows[0].isFulfilled)
        #expect(rows[1].requestSignupID == 12)
        #expect(rows[1].offerPseud == "FormerGiver")
        #expect(rows[1].isDefaulted && !rows[1].isCovered && !rows[1].isFulfilled)
        #expect(rows[2].pinchHitterPseud == "Replacement")
        #expect(rows[2].isCovered && !rows[2].isDefaulted && !rows[2].isFulfilled)
        #expect(!rows[3].isMatched)
        #expect(throws: AO3Error.self) {
            try AO3Client.parseChallengeAssignmentsPage("<h2 class='heading'>Assignments</h2>", slug: "fest", page: 1)
        }
    }

    @Test func assignmentJoinFetchesEveryPageIncludingOpenAssignments() async throws {
        var fetched: [String] = []
        let assignments = try await AO3Client.allChallengeAssignments { list, page in
            fetched.append("\(list.rawValue):\(page)")
            return AO3ChallengeAssignmentPage(
                assignments: [AO3ChallengeAssignment(id: page, collectionSlug: "fest")],
                currentPage: page, totalPages: list == .unfulfilled ? 3 : 2
            )
        }
        #expect(fetched == ["assignments:1", "assignments:2", "unfulfilled:1", "unfulfilled:2",
                            "unfulfilled:3", "defaults:1", "defaults:2"])
        // 1cb's Matched and 1by's count read this list: Complete plus Open (Q3).
        #expect(AO3ChallengeAssignmentList.sent == [.assignments, .unfulfilled])
        #expect(assignments.count == 7)
        let url = AO3ChallengeURL.assignments(slug: "fest", list: .unfulfilled, page: 3)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "unfulfilled", value: "true")))
        #expect(items.contains(URLQueryItem(name: "page", value: "3")))
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
        // Works are due on assignments_due_at; works_reveal_at is the reveal.
        #expect(form.settings.worksDueAt.postedString == "2026-03-01 00:00:00")
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

    /// challenge/shared/_challenge_requests rendering prompts/_prompt_blurb and
    /// _prompt_controls (otwarchive 00ad85b4): the li has no "prompt" class, the
    /// id is only on the Claim button or the owner's prompt links, and the
    /// viewer's own claim is the Drop Claim link.
    @Test func promptMemeReadsAO3sPromptBlurbs() throws {
        let html = """
        <html><body>
        <h2 class="heading">Prompts for Winter Meme</h2>
        <ul class="prompt index group">
          <li class="blurb group" role="article">
            <div class="header module">
              <h4 class="heading">Request by Anonymous</h4>
              <h5 class="fandoms heading"><span class="landmark">Fandom:</span>
                <a class="tag" href="/tags/Good%20Omens%20(TV)/works">Good Omens (TV)</a> &nbsp;</h5>
              <p class="datetime">04 Nov 2026</p>
            </div>
            <h6 class="landmark heading">Tags</h6>
            <ul class="tags commas"><li class="freeforms"><a class="tag" href="/tags/x/works">Slow Burn</a></li>
              <li class="tag">Any Character</li></ul>
            <h6 class="optional heading">Optional Tags:</h6>
            <ul class="optional tags commas"><li><a class="tag" href="/tags/y/works">No Beta</a></li></ul>
            <h6 class="landmark heading">Summary</h6>
            <blockquote class="userstuff summary"><p>A bookshop that rearranges itself.</p></blockquote>
            <ul class="actions" role="menu"><li><form class="button_to" method="post"
              action="/collections/meme/claims?prompt_id=12"><button type="submit">Claim</button></form></li></ul>
          </li>
          <li class="own blurb group" role="article">
            <div class="header module">
              <h4 class="heading">Four days of silence by ninesofswords (nine)</h4>
              <h5 class="fandoms heading"><span class="landmark">Fandom:</span>
                <a class="tag" href="/tags/sw/works">Star Wars</a>, <a class="tag" href="/tags/t/works">Trek</a></h5>
            </div>
            <ul class="tags commas"></ul>
            <blockquote class="userstuff summary"><p>Two pilots, one ship.</p></blockquote>
            <ul class="actions" role="menu">
              <li><a href="/collections/meme/prompts/13/edit">Edit Prompt</a></li>
              <li><a href="/collections/meme/works/new?claim_id=7">Fulfill</a></li>
              <li><a data-confirm="Do you really want to drop this claim?" rel="nofollow" data-method="delete"
                href="/collections/meme/claims/7">Drop Claim</a></li>
            </ul>
            <div class="claims listbox group"><h5 class="heading">Claimed By</h5>
              <ul class="commas index group"><li>nine</li><li>kestrel</li></ul></div>
          </li>
        </ul>
        </body></html>
        """
        let page = try AO3Client.parsePromptMemePage(html, slug: "meme", page: 1)
        try #require(page.prompts.count == 2)
        let anonymous = page.prompts[0]
        #expect(anonymous.id == 12)
        #expect(anonymous.canClaim && !anonymous.isClaimed)
        #expect(anonymous.isAnonymous && anonymous.displayedOwner == nil)
        #expect(anonymous.title.isEmpty)
        // The fandom is the kicker, kept off the tag line; optional tags stay out.
        #expect(anonymous.fandoms == ["Good Omens (TV)"])
        #expect(anonymous.tagSummary == "Slow Burn, Any Character")
        #expect(anonymous.promptText == "A bookshop that rearranges itself.")
        let mine = page.prompts[1]
        #expect(mine.id == 13)
        #expect(mine.title == "Four days of silence")
        #expect(mine.displayedOwner == "ninesofswords (nine)")
        #expect(mine.fandoms == ["Star Wars", "Trek"])
        #expect(mine.claimedByCurrentUser && mine.claimID == 7)
        #expect(mine.claimantCount == 2 && !mine.canClaim)
        // A page with no prompts is recognised by its heading, not treated as broken.
        let empty = try AO3Client.parsePromptMemePage(
            "<h2 class='heading'>Prompts for Winter Meme</h2><ul class='prompt index group'></ul>",
            slug: "meme", page: 1
        )
        #expect(empty.prompts.isEmpty)
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
        try #require(form.requests.count == 1)
        #expect(form.requests[0].fandoms == ["Star Wars"])
        try #require(form.offers.count == 1)
        #expect(form.offers[0].fandoms == ["Trek"])
        // AO3's own prompt ids round-trip into the POST, each in its own list.
        #expect(form.requests[0].id == 21 && form.offers[0].id == 22)
        let params = AO3Client.challengeSignUpParameters(form)
        #expect(params.contains { $0 == ("challenge_signup[requests_attributes][0][id]", "21") })
        #expect(params.contains { $0 == ("challenge_signup[offers_attributes][0][id]", "22") })
    }

    /// Rows show only live prompts, so an earlier prompt marked for removal
    /// shifts every position: edits must land on the prompt by id.
    @Test func promptEditsLandOnThePromptByID() throws {
        var form = AO3ChallengeSignUpForm(
            actionURL: try #require(URL(string: "https://archiveofourown.org/collections/fest/signups/4")),
            csrfToken: "csrf", collectionSlug: "fest", pseudID: "15",
            requests: [
                AO3ChallengePrompt(id: 21, kind: .request, promptText: "First", destroy: true),
                AO3ChallengePrompt(id: 22, kind: .request, promptText: "Second")
            ],
            offers: [AO3ChallengePrompt(id: -1, kind: .offer)]
        )
        // The first live row is prompt 22, at position 0 on screen.
        var second = try #require(form.prompt(id: 22, kind: .request))
        second.promptText = "Edited"
        form.updatePrompt(second)
        #expect(form.requests.map(\.promptText) == ["First", "Edited"])
        // Same id, other kind: an offer's draft id never reaches a request.
        #expect(form.prompt(id: -1, kind: .request) == nil)
        // A prompt that has gone is not recreated, and nothing positive is invented.
        form.updatePrompt(AO3ChallengePrompt(id: 99, kind: .request, promptText: "Ghost"))
        #expect(form.requests.map(\.id) == [21, 22])
    }
}
