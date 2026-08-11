import SwiftUI

/// Cheap stand-in for Home / Library (and similar dashboard tabs) while real
/// carousels are still being prepared. Intentionally avoids `@Query`, filters,
/// and real cover art so Liquid Glass tab morphs can finish without hitching on
/// a heavy first layout pass.
struct TabDashboardShell: View {
    /// When non-nil, applies as the navigation title (outer progressive shell).
    /// When nil, the host's existing `navigationTitle` is left alone (inner cache shell).
    var title: String?
    var sectionTitles: [String]
    var showFilterChips: Bool = false

    init(
        title: String? = nil,
        sectionTitles: [String] = ["Reading Now", "Saved for Later", "Finished"],
        showFilterChips: Bool = false
    ) {
        self.title = title
        self.sectionTitles = sectionTitles
        self.showFilterChips = showFilterChips
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showFilterChips {
                    filterChipRow
                }
                ForEach(sectionTitles, id: \.self) { sectionTitle in
                    skeletonSection(title: sectionTitle)
                }
            }
            .padding(.vertical, 12)
        }
        .modifier(OptionalNavigationTitle(title: title))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title ?? "Content"), loading")
    }

    /// Applies large inline title only when this shell owns the navigation chrome.
    private struct OptionalNavigationTitle: ViewModifier {
        let title: String?

        func body(content: Content) -> some View {
            if let title {
                content
                    .navigationTitle(title)
                    #if os(iOS)
                    .toolbarTitleDisplayMode(.inlineLarge)
                    #endif
            } else {
                content
            }
        }
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    SkeletonBlock(height: 28, width: 88, cornerRadius: 14)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityHidden(true)
    }

    private func skeletonSection(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        WorkCoverCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Mounts heavy tab roots only after a cheap shell has painted, so the system
/// tab bar's Liquid Glass selection morph isn't competing with Home/Library's
/// first `@Query` + carousel layout.
///
/// Once real content is built it stays mounted — later tab switches are free.
struct ProgressiveTabContent<Content: View>: View {
    enum ShellStyle {
        /// Home / Library style dashboard skeleton.
        case dashboard(title: String, sections: [String], showFilterChips: Bool)
        /// Lightweight fill — Browse / Account / Search don't need fake carousels.
        case blank
    }

    let shell: ShellStyle
    /// How long to keep the shell up so the tab glass morph can complete first.
    /// ~160ms covers a typical iOS tab selection animation without feeling laggy.
    var shellDuration: Duration = .milliseconds(160)
    @ViewBuilder var content: () -> Content

    @State private var showContent = false

    var body: some View {
        Group {
            if showContent {
                content()
            } else {
                shellView
            }
        }
        .task {
            guard !showContent else { return }
            // Let the current frame (and glass morph start) commit, then hold the
            // shell through the morph before paying for the real hierarchy.
            await Task.yield()
            try? await Task.sleep(for: shellDuration)
            guard !Task.isCancelled else { return }
            showContent = true
        }
    }

    @ViewBuilder
    private var shellView: some View {
        switch shell {
        case let .dashboard(title, sections, showFilterChips):
            NavigationStack {
                TabDashboardShell(
                    title: title,
                    sectionTitles: sections,
                    showFilterChips: showFilterChips
                )
            }
        case .blank:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}
