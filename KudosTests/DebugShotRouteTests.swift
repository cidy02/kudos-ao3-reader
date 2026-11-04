import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Every screen A82 names is a `shot:<name>` the debug map knows.
struct DebugShotRouteTests {
    @Test func everyA82ShotNameIsMapped() {
        let names = [
            "libpicker", "queuesettings", "newqueue", "editqueue", "addworks",
            "queuetag", "queuetags", "queuetagedit", "bulktag", "addtoqueue",
            "queuestorage", "collectiondetails", "newcollection", "collectionreorder",
            "addtocollection", "fandomlist", "fandomworks", "tagworks", "fandomfilter",
            "savesearch", "pagejump", "languagepicker", "tagpicker", "downloaddate",
            "seriespreserve", "bookmarkform", "readercontents", "readerfind",
            "readerdisplay", "readernote", "pronunciations", "pronunciationedit",
            "customizetheme", "formattingtray", "chapterpicker", "inboxfilter",
            "authorabout", "seriesdetail", "seriesedit", "seriesreorder", "seriesremove",
            "authorworksfilter", "colitems", "colsfilter", "chsettingsedit",
            "chsignupdetail", "prompttags", "tagset", "tagseteditor", "writingpreview",
            "chapters", "chapterform", "edittags", "tagseditor", "texteditor", "recovery",
            "seriespicker", "collectionsgifts", "creatorspicker", "parentpicker",
            "bulkedit", "bulktagstate", "bulknames", "prefhelp", "privacydata",
            "availability", "pairing", "revokedevice", "backupimport", "aboutkudos",
            "authorbookmarks", "readerspeech", "libfilter", "libselect", "remoteselect",
            "expandrow", "searchfilters", "collectionaddworks", "libedit", "sortby",
            "readerend", "welcome", "protectlibrary", "recentlydeleted",
        ]
        #expect(names.count == 84)
        for name in names {
            #expect(DebugShots.byName[name] != nil)
            #expect(!DebugShots.byName[name]!.route.isEmpty)
        }
        #expect(Set(DebugShots.names) == Set(names))
    }

    @MainActor
    @Test func fid48RoutesPinWantedScreenAndState() throws {
        // Board 05: newqueue opens the "New Queue" modal sheet over the queues organizer
        let newQueue = try #require(DebugShots.byName["newqueue"])
        #expect(newQueue.route == "queues")
        #expect(newQueue.sheets.contains("newqueue"))

        // Board 08: recentlydeleted routes to recentlyDeleted in select mode
        let recentlyDeleted = try #require(DebugShots.byName["recentlydeleted"])
        #expect(recentlyDeleted.route == "recentlyDeleted")
        #expect(recentlyDeleted.sheets.contains("recentlydeleted"))

        // Board 09: libselect routes to "Reading Now" shelf list in select mode
        let libSelect = try #require(DebugShots.byName["libselect"])
        #expect(libSelect.route == "section:readingNow")
        #expect(libSelect.sheets.contains("libselect"))

        // Board 29: readerfind has an active search query for chapter snippet results
        let readerFind = try #require(DebugShots.byName["readerfind"])
        #expect(readerFind.route == "read:Sodium Lights")
        #expect(readerFind.sheets.contains("readerfind"))
        #expect(readerFind.query == "lights")

        // Board 43: texteditor pushes the chapter text editor for posted work
        let textEditor = try #require(DebugShots.byName["texteditor"])
        #expect(textEditor.route == "acct:workedit:1001")
        #expect(textEditor.pushes.contains("texteditor"))

        // Verify runtime route resolution for readerfind query
        let defaults = UserDefaults.standard
        let oldRoute = defaults.object(forKey: "KudosDebugRoute")
        defer {
            if let oldRoute {
                defaults.set(oldRoute, forKey: "KudosDebugRoute")
            } else {
                defaults.removeObject(forKey: "KudosDebugRoute")
            }
        }
        defaults.set("shot:readerfind", forKey: "KudosDebugRoute")
        #expect(DebugLaunchRoute.findInWorkQuery == "lights")

        defaults.set("shot:recentlydeleted", forKey: "KudosDebugRoute")
        #expect(DebugLaunchRoute.pageRoute == "recentlyDeleted")
        #expect(DebugLaunchRoute.wantsSheet("recentlydeleted"))

        defaults.set("shot:libselect", forKey: "KudosDebugRoute")
        #expect(DebugLaunchRoute.pageRoute == "section:readingNow")
        #expect(DebugLaunchRoute.wantsSheet("libselect"))
    }

    @MainActor
    @Test func readerEndShotTargetsWorkWithAO3ID() throws {
        let defaults = UserDefaults.standard
        let oldDemo = defaults.object(forKey: "KudosDemoLibrary")
        let oldRoute = defaults.object(forKey: "KudosDebugRoute")
        defer {
            if let oldDemo {
                defaults.set(oldDemo, forKey: "KudosDemoLibrary")
            } else {
                defaults.removeObject(forKey: "KudosDemoLibrary")
            }
            if let oldRoute {
                defaults.set(oldRoute, forKey: "KudosDebugRoute")
            } else {
                defaults.removeObject(forKey: "KudosDebugRoute")
            }
        }

        defaults.set(true, forKey: "KudosDemoLibrary")
        defaults.set("shot:readerend", forKey: "KudosDebugRoute")

        let schema = Schema([SavedWork.self, ReadingQueue.self, WorkCollection.self, Tag.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        DemoLibrary.seedIfRequested(in: container.mainContext)
        let works = try container.mainContext.fetch(FetchDescriptor<SavedWork>())
        let target = try #require(DebugLaunchRoute.homeWork(in: works))
        #expect(target.ao3WorkID != nil)
    }
}
