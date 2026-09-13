import Foundation
import Testing
@testable import Kudos

struct AO3CollectionParsingTests {

    @Test func fourIndependentCollectionFlagsParseTogether() throws {
        let html = """
        <html><body>
        <ul class="collection index group">
          <li class="collection picture blurb group">
            <div class="header module group">
              <h4 class="heading">
                <a href="/collections/all_four">All Four Flags</a>
                <span class="name">(all_four)</span>
                by <a class="owner" href="/users/OwnerAccount">Owner</a>
              </h4>
              <p class="datetime">10 Jan 2026</p>
            </div>
            <blockquote class="userstuff summary">A closed moderated unrevealed anonymous fest.</blockquote>
            <p class="type">(Closed, Moderated, Unrevealed, Anonymous, Gift Exchange Challenge)</p>
            <dl class="stats">
              <dt class="works">Works:</dt><dd class="works">12</dd>
              <dt class="bookmarks">Bookmarked Items:</dt><dd class="bookmarks">3</dd>
            </dl>
          </li>
        </ul>
        </body></html>
        """
        let collections = try AO3Client.parseCollectionBlurbs(from: html)
        #expect(collections.count == 1)
        let collection = try #require(collections.first)
        #expect(collection.name == "all_four")
        #expect(collection.title == "All Four Flags")
        #expect(collection.isClosed)
        #expect(collection.isModerated)
        #expect(collection.isUnrevealed)
        #expect(collection.isAnonymous)
        #expect(collection.challengeKind == .giftExchange)
        #expect(collection.worksCount == 12)
        #expect(collection.bookmarksCount == 3)
        // The four flags are independent — open + unmoderated is a different collection.
        let openFlags = AO3Client.parseCollectionFlags(
            fromTypeText: "(Open, Unmoderated, Prompt Meme Challenge)"
        )
        #expect(!openFlags.closed)
        #expect(!openFlags.moderated)
        #expect(!openFlags.unrevealed)
        #expect(!openFlags.anonymous)
        #expect(openFlags.kind == .promptMeme)
    }

    @Test func existingParseCollectionsStillReadsNameTitleAndMaintainers() throws {
        let html = """
        <html><body>
        <ul class="collection index group">
          <li class="collection picture blurb group">
            <div class="header module group">
              <h4 class="heading">
                <a href="/collections/cool_fics">Cool Fics</a> by
                <a class="owner" href="/users/OwnerAccount">Owner Pseud</a> and
                <a class="mod" href="/users/ModAccount">Mod Pseud</a>
              </h4>
            </div>
          </li>
        </ul>
        </body></html>
        """
        let collections = try AO3Client.parseCollections(from: html)
        #expect(collections.count == 1)
        #expect(collections[0].name == "cool_fics")
        #expect(collections[0].title == "Cool Fics")
        #expect(collections[0].maintainerNames == ["Owner Pseud", "Mod Pseud"])
        #expect(!collections[0].isClosed)
        #expect(!collections[0].isModerated)
        #expect(!collections[0].isUnrevealed)
        #expect(!collections[0].isAnonymous)
    }

    @Test func itemApprovalTabsAndStagedFieldsParse() throws {
        let html = """
        <html><body>
        <h2 class="heading">Items in <a href="/collections/fest">Fest</a></h2>
        <ul class="navigation actions" role="navigation">
          <li><span class="current">Unreviewed by Collection</span></li>
          <li><a href="/collections/fest/items?status=unreviewed_by_user">Unreviewed by User</a></li>
          <li><a href="/collections/fest/items?status=rejected_by_collection">Rejected by Collection</a></li>
          <li><a href="/collections/fest/items?status=rejected_by_user">Rejected by User</a></li>
          <li><a href="/collections/fest/items?status=approved">Approved</a></li>
        </ul>
        <form action="/collections/fest/items/update_multiple" method="post">
          <input type="hidden" name="authenticity_token" value="csrf-item">
          <input type="hidden" name="_method" value="patch">
          <ul class="index group">
            <li class="collection item picture blurb group">
              <div class="header module">
                <h4 class="heading" id="collection_item_42">
                  <a href="/works/99">Queued Work</a>
                </h4>
                <h5 class="heading">Creator Pseud (Member)</h5>
              </div>
              <ul class="actions">
                <li class="user status">
                  <select name="collection_items[42][user_approval_status]">
                    <option value="unreviewed"></option>
                    <option value="approved" selected>Approved</option>
                    <option value="rejected">Rejected</option>
                  </select>
                </li>
                <li class="collection status">
                  <select name="collection_items[42][collection_approval_status]">
                    <option value="unreviewed" selected></option>
                    <option value="approved">Approved</option>
                    <option value="rejected">Rejected</option>
                  </select>
                </li>
                <li>
                  <input type="checkbox" name="collection_items[42][unrevealed]" value="1" checked>
                </li>
                <li>
                  <input type="checkbox" name="collection_items[42][anonymous]" value="1">
                </li>
              </ul>
            </li>
          </ul>
        </form>
        </body></html>
        """
        let tabs = try AO3Client.parseCollectionItemTabs(from: html)
        #expect(tabs.contains(.unreviewed))
        #expect(tabs.contains(.invited))
        #expect(tabs.contains(.rejected))
        #expect(tabs.contains(.rejectedByUser))
        #expect(tabs.contains(.approved))

        let page = try AO3Client.parseCollectionItemsPage(
            html, slug: "fest", tab: .unreviewed, page: 1
        )
        #expect(page.items.count == 1)
        let item = try #require(page.items.first)
        #expect(item.id == 42)
        #expect(item.workTitle == "Queued Work")
        #expect(item.workID == 99)
        #expect(item.creatorApproval == .approved)
        #expect(item.moderatorApproval == .unreviewed)
        #expect(item.isUnrevealed)
        #expect(!item.isAnonymous)
        #expect(item.userApprovalField == "collection_items[42][user_approval_status]")
        #expect(item.collectionApprovalField == "collection_items[42][collection_approval_status]")
        #expect(page.csrfToken == "csrf-item")
        #expect(page.httpMethodOverride == "patch")
        #expect(page.actionURL.path.hasSuffix("/collections/fest/items/update_multiple"))
    }

    @Test func collectionFormParsesHeaderPreferencesProfileAndFourFlags() throws {
        let html = """
        <html>
        <head><meta name="csrf-token" content="csrf-form"></head>
        <body>
        <form class="verbose post collection" action="/collections/fest" method="post">
          <input type="hidden" name="_method" value="put">
          <input type="hidden" name="authenticity_token" value="csrf-form">
          <fieldset>
            <legend>Header</legend>
            <input name="collection[name]" value="fest">
            <input name="collection[title]" value="Winter Fest">
            <input name="collection[parent_name]" value="parent_fest">
            <input name="collection[email]" value="mod@example.com">
            <input name="collection[header_image_url]" value="https://example.com/header.png">
            <input name="collection[icon_alt_text]" value="icon alt">
            <input name="collection[icon_comment_text]" value="icon comment">
            <textarea name="collection[description]">Brief</textarea>
          </fieldset>
          <fieldset>
            <legend>Preferences</legend>
            <input type="hidden" name="collection[collection_preference_attributes][id]" value="7">
            <input type="checkbox" name="collection[collection_preference_attributes][closed]" value="1" checked>
            <input type="checkbox" name="collection[collection_preference_attributes][moderated]" value="1" checked>
            <input type="checkbox" name="collection[collection_preference_attributes][unrevealed]" value="1" checked>
            <input type="checkbox" name="collection[collection_preference_attributes][anonymous]" value="1" checked>
          </fieldset>
          <fieldset class="profile">
            <legend>Profile</legend>
            <input type="hidden" name="collection[collection_profile_attributes][id]" value="8">
            <textarea name="collection[collection_profile_attributes][intro]">Hello</textarea>
            <textarea name="collection[collection_profile_attributes][faq]">FAQ</textarea>
            <textarea name="collection[collection_profile_attributes][rules]">Be kind</textarea>
          </fieldset>
        </form>
        </body></html>
        """
        let form = try AO3Client.parseCollectionForm(html, slug: "fest")
        #expect(form.name == "fest")
        #expect(form.nameIsLocked)
        #expect(form.title == "Winter Fest")
        #expect(form.parentName == "parent_fest")
        #expect(form.email == "mod@example.com")
        #expect(form.headerImageURL.contains("header.png"))
        #expect(form.iconAlt == "icon alt")
        #expect(form.iconComment == "icon comment")
        #expect(form.introduction == "Hello")
        #expect(form.faq == "FAQ")
        #expect(form.rules == "Be kind")
        #expect(form.isClosed && form.isModerated && form.isUnrevealed && form.isAnonymous)
        #expect(form.deleteOpenOnAO3?.path.hasSuffix("/collections/fest/confirm_delete") == true)
        #expect(form.closeOpenOnAO3?.path.hasSuffix("/collections/fest/edit") == true)
        let params = Dictionary(uniqueKeysWithValues: AO3Client.collectionFormParameters(form))
        #expect(params[AO3CollectionParam.closed] == "1")
        #expect(params[AO3CollectionParam.moderated] == "1")
        #expect(params[AO3CollectionParam.unrevealed] == "1")
        #expect(params[AO3CollectionParam.anonymous] == "1")
    }

    @Test func nameAvailabilityHeuristic() {
        #expect(AO3Client.interpretCollectionNameAvailability(httpStatus: 404) == .available)
        #expect(AO3Client.interpretCollectionNameAvailability(httpStatus: 200) == .taken)
        #expect(AO3Client.interpretCollectionNameAvailability(httpStatus: 403) == .unknown)
        #expect(AO3Client.interpretCollectionNameAvailability(httpStatus: 500) == .unknown)
        #expect(AO3Client.interpretCollectionNameAvailability(error: .notFound) == .available)
        #expect(AO3Client.interpretCollectionNameAvailability(error: .forbidden) == .unknown)
        #expect(AO3Client.collectionNameFormatIsValid("fest_2026"))
        #expect(!AO3Client.collectionNameFormatIsValid("a"))
        #expect(!AO3Client.collectionNameFormatIsValid("has space"))
        #expect(!AO3Client.collectionNameFormatIsValid("_leading"))
        #expect(AO3CollectionURL.reservedSlugs.contains("new"))
    }

    /// Singular heading, plus an href carrying a trailing path segment — the
    /// profile page links `/tag_sets/<id>` but a nominations link must still
    /// yield the id rather than nil.
    @Test func collectionProfileTagSetSingular() throws {
        let html = """
        <html><body>
        <dl class="meta group">
          <dt>Challenge Type:</dt><dd>Gift Exchange</dd>
          <dt>Tag Set:</dt>
          <dd>
            <ul class="commas">
              <li><a href="/tag_sets/123/nominations">Winter Fest Tag Set</a></li>
            </ul>
          </dd>
        </dl>
        </body></html>
        """
        let links = try AO3Client.parseCollectionTagSets(html)
        #expect(links.count == 1)
        #expect(links[0].id == 123)
        #expect(links[0].title == "Winter Fest Tag Set")
    }

    @Test func collectionProfileTagSetsPlural() throws {
        let html = """
        <html><body>
        <dl class="meta group">
          <dt>Tag Sets:</dt>
          <dd>
            <ul class="commas">
              <li><a href="/tag_sets/7">Fandoms</a></li>
              <li><a href="https://archiveofourown.org/tag_sets/8?page=2">Characters</a></li>
              <li><a href="/tag_sets/new">Not an id</a></li>
            </ul>
          </dd>
        </dl>
        </body></html>
        """
        let links = try AO3Client.parseCollectionTagSets(html)
        // "/tag_sets/new" is skipped rather than becoming a row that pushes id 0.
        #expect(links.map(\.id) == [7, 8])
        #expect(links.map(\.title) == ["Fandoms", "Characters"])
    }

    /// Absence is the normal case — most collections have no challenge — so the
    /// parse returns an empty list instead of throwing.
    @Test func collectionProfileWithoutTagSetBlockReturnsEmpty() throws {
        let html = """
        <html><body>
        <dl class="meta group">
          <dt>Challenge Type:</dt><dd>None</dd>
          <dt>Maintainers:</dt><dd><a href="/users/alice">Alice</a></dd>
        </dl>
        </body></html>
        """
        #expect(try AO3Client.parseCollectionTagSets(html).isEmpty)
    }

    @Test func collectionPeopleParse() throws {
        let html = """
        <html><body>
        <h2 class="heading">Participants in Fest</h2>
        <ul class="participant pseud index group">
          <li class="user pseud picture blurb group">
            <h4 class="heading"><a href="/users/alice">Alice</a></h4>
            <dl class="stats"><dt class="works">Works</dt><dd class="works">4</dd></dl>
          </li>
        </ul>
        </body></html>
        """
        let page = try AO3Client.parseCollectionPeoplePage(html, page: 1)
        #expect(page.people.count == 1)
        #expect(page.people[0].identity.displayName == "Alice")
        #expect(page.people[0].workCount == 4)
    }
}
