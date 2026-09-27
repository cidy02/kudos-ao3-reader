import Foundation
import Testing
@testable import Kudos

/// Challenge forms read against otwarchive's own templates (master 00ad85b4):
/// the fixtures are reconstructed from the ERB, not production captures.
struct AO3ChallengeFormTests {

    /// challenge_signups/_signup_form + prompts/_prompt_form_tag_options: a
    /// fieldset per prompt type headed `allowed_range_string`, and one label per
    /// tag type the challenge allows, written by `challenge_signup_label`.
    static func signUpForm(offers: Bool) -> String {
        let offerFieldset = offers ? """
        <fieldset>
          <legend>Offers</legend>
          <h3 class="heading">Offers (1)</h3>
          <div class="removeme"><fieldset class="tagset">
            <legend>Offer 1</legend><h3 class="heading">Offer 1</h3>
            <dl>
              <dt class="required"><label class="fandom"
                for="challenge_signup_offers_attributes_0_tag_set_attributes_fandom_tagnames">Fandom (1): *</label></dt>
              <dd><input type="text" name="challenge_signup[offers_attributes][0][tag_set_attributes][fandom_tagnames]"
                id="challenge_signup_offers_attributes_0_tag_set_attributes_fandom_tagnames" value="Trek"></dd>
            </dl>
          </fieldset></div>
        </fieldset>
        """ : ""
        return """
        <html><head><meta name="csrf-token" content="csrf-signup"></head><body>
        <form action="/collections/fest/signups" method="post">
          <input type="hidden" name="authenticity_token" value="csrf-signup">
          <fieldset>
            <legend>Requests</legend>
            <h3 class="heading">Requests (1 - 2)</h3>
            <div class="removeme"><fieldset class="tagset">
              <legend>Request 1</legend><h3 class="heading">Request 1</h3>
              <dl>
                <dt class="required"><label class="fandom"
                  for="challenge_signup_requests_attributes_0_tag_set_attributes_fandom_tagnames">Fandoms (1 - 2): *</label></dt>
                <dd><input type="text" name="challenge_signup[requests_attributes][0][tag_set_attributes][fandom_tagnames]"
                  id="challenge_signup_requests_attributes_0_tag_set_attributes_fandom_tagnames" value=""></dd>
                <dt><label class="relationship"
                  for="challenge_signup_requests_attributes_0_tag_set_attributes_relationship_tagnames">Relationships (0 - 3):</label></dt>
                <dd><input type="text" name="challenge_signup[requests_attributes][0][tag_set_attributes][relationship_tagnames]"
                  id="challenge_signup_requests_attributes_0_tag_set_attributes_relationship_tagnames" value=""></dd>
                <dd class="any option"><label class="action">
                  <input name="challenge_signup[requests_attributes][0][any_relationship]" type="hidden" value="0">
                  <input type="checkbox" value="1" name="challenge_signup[requests_attributes][0][any_relationship]">
                  Any Relationship</label></dd>
              </dl>
            </fieldset></div>
          </fieldset>
          \(offerFieldset)
        </form></body></html>
        """
    }

    @Test func signUpFormReadsPromptAndTagLimits() throws {
        let form = try AO3Client.parseChallengeSignUpForm(Self.signUpForm(offers: true), slug: "fest")
        let limits = try #require(form.limits)
        #expect(limits == AO3ChallengeSignUpLimits(
            requestsRequired: 1, requestsAllowed: 2, offersRequired: 1, offersAllowed: 1
        ))
        #expect(form.takesOffers)
        #expect(form.requestTagLimits == [.fandom: 1...2, .relationship: 0...3])
        #expect(form.offerTagLimits == [.fandom: 1...1])

        // A prompt meme's form has a Requests fieldset and nothing else.
        let meme = try AO3Client.parseChallengeSignUpForm(Self.signUpForm(offers: false), slug: "meme")
        #expect(meme.limits?.offersAllowed == 0)
        #expect(!meme.takesOffers)
        #expect(meme.offerTagLimits == nil)
        // 1cc's "New prompt" posts this form: a request, and no offer at all.
        let params = AO3Client.challengeSignUpParameters(meme).map(\.0)
        #expect(params.contains("challenge_signup[requests_attributes][0][tag_set_attributes][fandom_tagnames]"))
        #expect(!params.contains { $0.contains("offers_attributes") })
    }

    /// Mirrors `Prompt#correct_number_of_tags`. A type with no field on the
    /// form (characters here) allows none; "Any" means no tags of that type.
    @Test func tagLimitsBlockSubmitWithAMessagePerPrompt() throws {
        var form = try AO3Client.parseChallengeSignUpForm(Self.signUpForm(offers: true), slug: "fest")
        let request = try #require(form.requests.first)
        // As loaded: no fandom yet, so the request is short of AO3's 1.
        let empty = form.validated()
        #expect(!empty.isValid)
        let message = try #require(empty.fieldErrors[AO3ChallengeSignUpForm.errorKey(for: request)])
        #expect(message == "Request 1: Choose 1 to 2 fandoms (you have 0).")
        #expect(empty.fieldErrors[AO3ChallengeSignUpForm.errorKey(for: form.offers[0])] == nil)

        var edited = request
        edited.fandoms = ["Good Omens (TV)"]
        edited.characters = ["Crowley"]
        edited.relationships = ["Aziraphale/Crowley"]
        edited.anyRelationship = true
        form.updatePrompt(edited)
        let problems = form.validated().fieldErrors[AO3ChallengeSignUpForm.errorKey(for: edited)]
        #expect(problems == "Request 1: This challenge takes no characters. "
            + "Choose relationships or “Any”, not both.")

        edited.characters = []
        edited.relationships = []
        form.updatePrompt(edited)
        #expect(form.validated().isValid)
    }

    /// 1cb: defaulted-and-uncovered rows are the open pinch hits; AO3's Pinch
    /// Hits list is the claimed ones. Open lead, numbered straight through.
    @Test func pinchHitRowsPutOpenOnesFirst() {
        let open = AO3ChallengeAssignment(
            id: 82, collectionSlug: "fest", requestPseud: "tidewrack", offerPseud: "FormerGiver", isDefaulted: true
        )
        let claimed = AO3ChallengeAssignment(
            id: 83, collectionSlug: "fest", requestPseud: "Casey", offerPseud: "paperlanterns",
            pinchHitterPseud: "paperlanterns", isCovered: true
        )
        let rows = AO3PinchHitRow.rows(open: [open], claimed: [claimed])
        #expect(rows.map(\.number) == [1, 2])
        #expect(rows.map(\.isOpen) == [true, false])
        #expect(rows[0].detail(dueText: "1 Dec 2026") == "Requested by tidewrack")
        #expect(rows[1].detail(dueText: "1 Dec 2026") == "Claimed by paperlanterns for Casey · due 1 Dec 2026")
        #expect(rows[1].detail(dueText: nil) == "Claimed by paperlanterns for Casey")
    }
}
