import Foundation

/// Which kudos / comments / bookmarks / hits figure Work Details prints when it
/// holds two (1a.5): the remote summary's, from the listing it was opened from or
/// the refresh it just ran, or the saved work's, from the library's last metadata
/// refresh. The remote one is the fresher fetch, so it wins whenever it has a
/// figure, a printed zero included. The stored one fills in when it has none (a
/// sparse Subscriptions row carries no stats), and only when it is above zero,
/// since a stored zero is as likely "never refreshed" as a real zero.
enum WorkDetailFigures {
    static func preferred(local: Int?, remote: Int?) -> Int? {
        if let remote { return remote }
        if let local, local > 0 { return local }
        return nil
    }
}
