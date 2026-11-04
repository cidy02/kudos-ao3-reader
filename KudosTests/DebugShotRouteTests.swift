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
            "readerend", "welcome", "protectlibrary",
        ]
        #expect(names.count == 83)
        for name in names {
            #expect(DebugShots.byName[name] != nil)
            #expect(!DebugShots.byName[name]!.route.isEmpty)
        }
        #expect(Set(DebugShots.names) == Set(names))
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
