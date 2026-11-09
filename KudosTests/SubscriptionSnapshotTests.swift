#if os(iOS)

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Kudos

@MainActor
@Suite(.serialized)
struct SubscriptionSnapshotTests {
    private nonisolated static let outputPath = ProcessInfo.processInfo.environment["KUDOS_SNAPSHOT_DIR"]

    @Test(.enabled(if: outputPath != nil))
    func renderSubscriptionScreens() async throws {
        guard let outputPath = Self.outputPath else { return }

        let outputDirectory = URL(
            fileURLWithPath: NSString(string: outputPath).expandingTildeInPath,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let defaultsName = "SubscriptionSnapshotTests"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw SnapshotError.defaultsUnavailable
        }
        defaults.removePersistentDomain(forName: defaultsName)

        let standardDefaults = UserDefaults.standard
        let originalTheme = standardDefaults.object(forKey: "appTheme")
        defer {
            if let originalTheme {
                standardDefaults.set(originalTheme, forKey: "appTheme")
            } else {
                standardDefaults.removeObject(forKey: "appTheme")
            }
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        for screen in Screen.allCases {
            defaults.set(screen != .waitingOpen && screen != .waitingRows, forKey: "hideMatureContent")
            defaults.set(
                screen == .newToYouHidden
                    ? MaturePrivacyMode.hide.rawValue
                    : MaturePrivacyMode.obscure.rawValue,
                forKey: "matureContentMode"
            )

            for themeValue in ReaderTheme.allCases {
                for textSize in TextSize.allCases {
                    for display in Display.allCases {
                        let theme = ThemeManager()
                        theme.appTheme = themeValue
                        let root = screen.view
                            .environment(theme)
                            .environment(PrivacyGate())
                            .environment(AO3AuthService())
                            .defaultAppStorage(defaults)
                            .dynamicTypeSize(textSize.value)
                            .preferredColorScheme(theme.appTheme.colorScheme)
                            .tint(theme.effectiveTint)
                            // As the app shell does, so \.accentInk is the theme's legible step.
                            .accentTint(theme.effectiveTint, on: theme.appTheme)

                        let image = try await render(
                            AnyView(root),
                            size: display.size,
                            style: theme.appTheme.colorScheme == .dark ? .dark : .light
                        )
                        let filename = [
                            screen.rawValue,
                            themeValue.rawValue,
                            textSize.rawValue,
                            display.rawValue
                        ].joined(separator: "-") + ".png"
                        guard let data = image.pngData() else {
                            throw SnapshotError.pngEncodingFailed(filename)
                        }
                        try data.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
                    }
                }
            }
        }
    }

    /// `style` stands in for `preferredColorScheme`, which only reaches a window's
    /// root, not this child controller.
    private func render(_ root: AnyView, size: CGSize, style: UIUserInterfaceStyle) async throws -> UIImage {
        let frame = CGRect(origin: .zero, size: size)
        let controller = UIHostingController(rootView: root)
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            throw SnapshotError.windowSceneUnavailable
        }
        // The scene forces its windows to full screen, so lay the hosted view out
        // at the requested size inside a plain container and draw only that view.
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        container.overrideUserInterfaceStyle = style
        container.addChild(controller)
        controller.view.frame = frame
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)

        controller.view.layoutIfNeeded()
        for _ in 0..<3 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: frame, format: format)
        var didDraw = false
        let image = renderer.image { _ in
            didDraw = controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        guard didDraw else { throw SnapshotError.drawHierarchyFailed }
        return image
    }
}

private extension SubscriptionSnapshotTests {
    enum Screen: String, CaseIterable {
        case waiting
        /// The same sample with privacy off, so the rows themselves can be reviewed.
        case waitingOpen = "waiting-open"
        /// Home's update rows alone (T-506), privacy off, so the marker stays in frame at AX5.
        case waitingRows = "waiting-rows"
        case following
        case tidyUp = "tidy-up"
        case newToYou = "new-to-you"
        case newToYouHidden = "new-to-you-hidden"
        case sources
        case connectMail = "connect-mail"
        case coldScan = "cold-scan"
        case coldScanPaused = "cold-scan-paused"
        case scanBannerRunning = "scan-banner-running"
        case scanBannerPaused = "scan-banner-paused"
        case scanBannerRetry = "scan-banner-retry"
        case scanBannerMaintenance = "scan-banner-maintenance"

        var view: AnyView {
            switch self {
            case .waiting, .waitingOpen:
                AnyView(NavigationStack { WaitingListView.snapshotSample })
            case .waitingRows:
                AnyView(ScrollView {
                    let updates = WaitingListView.snapshotUpdates
                    VStack(spacing: 0) {
                        ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                            WaitingRow(
                                update: update,
                                position: index + 1,
                                showsPosition: false,
                                isFirst: index == 0,
                                isLast: index == updates.count - 1
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                })
            case .following:
                // One still-going work, so Series and Authors land inside the snapshot frame.
                AnyView(NavigationStack {
                    FollowingListView(
                        works: [
                            Self.work(101, "The Lantern Keeper", "saltwindow", complete: false, chapters: "9/?")
                        ],
                        unfollowed: .constant([]),
                        series: Self.followingSeries,
                        authors: Self.followingAuthors
                    )
                }
                .environment(AppRouter()))
            case .tidyUp:
                AnyView(NavigationStack {
                    FollowingListView(
                        works: Self.followingWorks,
                        deletedIDs: [104],
                        scope: .tidyUp,
                        unfollowed: .constant([])
                    )
                })
            case .newToYou:
                AnyView(NavigationStack {
                    NewToYouCardsView(cards: [
                        NewToYouCard(preview: Self.newWork, source: .author("saltwindow"))
                    ])
                })
            case .newToYouHidden:
                AnyView(NavigationStack {
                    NewToYouCardsView(cards: [
                        NewToYouCard(preview: Self.hiddenWork, source: .author("saltwindow"))
                    ])
                })
            case .sources:
                AnyView(NavigationStack {
                    UpdateSourcesView(
                        onScanAO3: {},
                        onConnectMail: { _, _ in }
                    )
                })
            case .connectMail:
                // A presented sheet is drawn outside the hosted view, so render its content.
                AnyView(MailConnectionView(onConnect: { _, _ in }))
            case .coldScan:
                AnyView(NavigationStack {
                    ColdStartScanView(
                        progress: .init(
                            phase: .running,
                            checked: 12,
                            total: 35,
                            username: "sample_reader",
                            remaining: .seconds(420)
                        )
                    )
                })
            case .coldScanPaused:
                AnyView(NavigationStack {
                    ColdStartScanView(
                        progress: .init(
                            phase: .paused,
                            checked: 12,
                            total: 35,
                            username: "sample_reader",
                            remaining: .seconds(420)
                        )
                    )
                })
            case .scanBannerRunning:
                Self.scanBanner(phase: .running, checked: 12, total: 35, remaining: .seconds(420))
            case .scanBannerPaused:
                Self.scanBanner(phase: .paused, checked: 12, total: 35, remaining: .seconds(420))
            case .scanBannerRetry:
                Self.scanBanner(
                    phase: .running,
                    checked: 12,
                    total: 35,
                    remaining: .seconds(420),
                    statusNote: "AO3 asked us to wait."
                )
            case .scanBannerMaintenance:
                Self.scanBanner(
                    phase: .stopped,
                    checked: 4,
                    total: 35,
                    statusNote: SubscriptionScanCopy.maintenance
                )
            }
        }

        /// Bottom overlay, the same place `ContentView` pins the app-wide banner.
        private static func scanBanner(
            phase: SubscriptionScanPhase,
            checked: Int,
            total: Int,
            remaining: Duration? = nil,
            statusNote: String? = nil
        ) -> AnyView {
            let scan = SubscriptionScanService(
                snapshot: phase,
                checked: checked,
                total: total,
                remaining: remaining,
                statusNote: statusNote
            )
            return AnyView(
                Color.clear
                    .overlay(alignment: .bottom) {
                        SubscriptionScanBanner()
                    }
                    .environment(scan)
            )
        }

        private static var followingWorks: [AO3WorkSummary] {
            [
                work(101, "The Lantern Keeper", "saltwindow", complete: false, chapters: "9/?"),
                work(102, "A Quiet Harbour", "marrowlight"),
                work(103, "Salt and Ember", "quietfern", complete: true, chapters: "24/24"),
                work(104, "Gone Dark", "wrenfield")
            ]
        }

        /// A missing series link is AO3's deleted subscribable: listed, not tappable.
        private static var followingSeries: [AO3FollowedSeries] {
            [
                AO3FollowedSeries(
                    subscriptionID: 501,
                    title: "The Lantern Cycle",
                    creatorNames: ["saltwindow"],
                    creatorIdentities: [],
                    seriesID: 50,
                    url: URL(string: "https://archiveofourown.org/series/50")
                ),
                AO3FollowedSeries(
                    subscriptionID: 502,
                    title: "Deleted item",
                    creatorNames: [],
                    creatorIdentities: [],
                    seriesID: nil,
                    url: nil
                )
            ]
        }

        private static var followingAuthors: [AO3FollowedAuthor] {
            [
                AO3FollowedAuthor(
                    subscriptionID: 601,
                    name: "marrowlight",
                    route: AO3AuthorRoute(username: "marrowlight")
                )
            ]
        }

        private static var newWork: AO3WorkSummary {
            var work = work(
                201,
                "The Lantern Keeper",
                "saltwindow",
                complete: false,
                chapters: "9/?"
            )
            work.fandoms = ["Original Work"]
            work.rating = "Teen And Up Audiences"
            work.warnings = ["Creator Chose Not To Use Archive Warnings"]
            work.summary = "A lighthouse keeper finds the lamp has been lit by someone else for years."
            work.words = 48_210
            work.kudos = 1_204
            work.dateUpdated = "2026-11-07"
            return work
        }

        private static var hiddenWork: AO3WorkSummary {
            var work = newWork
            work.rating = "Explicit"
            return work
        }

        private static func work(
            _ id: Int,
            _ title: String,
            _ author: String,
            complete: Bool? = nil,
            chapters: String = ""
        ) -> AO3WorkSummary {
            var work = AO3WorkSummary.subscription(id: id, title: title, authors: [author])
            work.isComplete = complete
            work.chapters = chapters
            return work
        }
    }

    enum TextSize: String, CaseIterable {
        case large
        case accessibility3
        case accessibility5

        var value: DynamicTypeSize {
            switch self {
            case .large: .large
            case .accessibility3: .accessibility3
            case .accessibility5: .accessibility5
            }
        }
    }

    enum Display: String, CaseIterable {
        case duoInner = "duo-inner"
        case cover

        var size: CGSize {
            switch self {
            case .duoInner: CGSize(width: 951, height: 669)
            case .cover: CGSize(width: 466, height: 678)
            }
        }
    }

    enum SnapshotError: Error {
        case defaultsUnavailable
        case windowSceneUnavailable
        case drawHierarchyFailed
        case pngEncodingFailed(String)
    }
}

private extension WaitingListView {
    static let snapshotNow = Date(timeIntervalSince1970: 1_794_038_400)

    static var snapshotSample: WaitingListView {
        WaitingListView(
            updates: snapshotUpdates,
            mailSince: snapshotNow - 3_456_000,
            unverifiedCount: 2
        )
    }

    static var snapshotUpdates: [SubscriptionUpdate] {
        let now = snapshotNow
        return [
            SubscriptionUpdate(
                uid: 1,
                workID: 301,
                chapterID: 3_010,
                chapterNumber: 9,
                isNewWork: false,
                isContested: false,
                isAnchoredToWork: true,
                workTitle: "The Lantern Keeper",
                author: "saltwindow",
                at: now,
                source: .work
            ),
            SubscriptionUpdate(
                uid: 2,
                workID: 302,
                chapterID: 3_020,
                chapterNumber: 3,
                isNewWork: false,
                isContested: false,
                isAnchoredToWork: false,
                workTitle: "A Quiet Harbour",
                author: "marrowlight",
                at: now - 3_600,
                source: .author("marrowlight")
            ),
            SubscriptionUpdate(
                uid: 3,
                workID: 303,
                chapterID: 3_030,
                chapterNumber: nil,
                isNewWork: true,
                isContested: false,
                isAnchoredToWork: true,
                workTitle: "Salt and Ember",
                author: "quietfern",
                at: now - 7_200,
                source: .work,
                extraCreations: 3
            )
        ]
    }
}

#endif
