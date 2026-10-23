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
            "authorbookmarks", "readerspeech",
        ]
        #expect(names.count == 72)
        for name in names {
            #expect(DebugShots.byName[name] != nil)
            #expect(!DebugShots.byName[name]!.route.isEmpty)
        }
        #expect(Set(DebugShots.names) == Set(names))
    }
}
