import SwiftUI
import SwiftData

/// The AO3 browsing tab: a web view with floating Liquid Glass controls that
/// captures EPUB downloads into the library and bookmarks pages.
struct BrowseView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var model = BrowserModel()
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            WebView(webView: model.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) { bannerView }
                .toolbar { browserToolbar }
                #if os(iOS)
                // Safari-style: hide the bottom tab bar while scrolling the page
                // down, reveal it on scroll up (driven by the web view's scroll).
                .toolbar(model.tabBarHidden ? .hidden : .visible, for: .tabBar)
                .animation(.easeInOut(duration: 0.25), value: model.tabBarHidden)
                #endif
                .onAppear { configureImport() }
                .onChange(of: router.pendingURL) { _, url in
                    if let url {
                        model.load(url)
                        router.pendingURL = nil
                    }
                }
        }
    }

    // MARK: Top toolbar (Safari-style)

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!model.canGoBack)

            // iOS uses edge-swipe gestures to go forward, so only Back is shown.
            #if !os(iOS)
            Button { model.goForward() } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!model.canGoForward)
            #endif
        }

        ToolbarItem(placement: .principal) {
            addressField
        }

        ToolbarItem(placement: .primaryAction) {
            Button { bookmarkCurrentPage() } label: {
                Image(systemName: "bookmark")
            }
        }
    }

    /// The Safari-like address/search field, built on the shared `GlassFieldBar`.
    private var addressField: some View {
        GlassFieldBar(
            text: $model.urlString,
            placeholder: "Search AO3 or enter a URL",
            submitLabel: .go,
            onSubmit: { model.loadFromAddressBar() }
        ) {
            Image(systemName: model.isLoading ? "arrow.trianglehead.clockwise" : "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, isActive: model.isLoading)
        } trailing: {
            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Banner

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Text(banner)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func configureImport() {
        let context = self.context
        model.onImport = { fileURL, source in
            // importEPUB is async (Readium opens the publication asynchronously);
            // the import callback is sync/fire-and-forget, so hop onto a Task.
            Task { @MainActor in
                if let work = await importEPUB(fileURL, source: source, into: context) {
                    show("Saved “\(work.title)” to Library")
                } else {
                    show("Couldn't save EPUB.")
                }
            }
        }
    }

    private func bookmarkCurrentPage() {
        guard let candidate = model.currentBookmark else { return }
        context.insert(Bookmark(title: candidate.title, urlString: candidate.url.absoluteString))
        try? context.save()
        show("Bookmarked “\(candidate.title)”")
    }

    private func show(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { banner = nil }
        }
    }
}
