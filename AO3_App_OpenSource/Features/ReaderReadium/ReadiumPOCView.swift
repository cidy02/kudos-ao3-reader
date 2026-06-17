#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import ReadiumShared
import ReadiumNavigator

/// Phase-0 proof-of-concept screen. Lets the user pick a local EPUB, opens it
/// with the Readium toolkit, and renders it through `EPUBNavigatorViewController`
/// with basic chapter/page navigation and live settings (scroll, theme, font
/// size). Reached from Settings ▸ Experimental; the production reader is unchanged.
struct ReadiumPOCView: View {
    @State private var model = ReadiumReaderModel()
    @State private var importing = false
    @State private var showChapters = false

    var body: some View {
        content
            .navigationTitle("Readium POC")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.epub]) { result in
                if case let .success(url) = result {
                    Task { await model.load(pickedURL: url) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            placeholder(
                systemImage: "book.closed",
                title: "Readium Reader",
                message: "Pick a local EPUB to open it with the Readium toolkit."
            )
        case .loading:
            ProgressView("Opening EPUB…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            placeholder(systemImage: "exclamationmark.triangle", title: "Couldn't open", message: message)
        case .ready:
            reader
        }
    }

    // MARK: Reader

    @ViewBuilder
    private var reader: some View {
        if let navigator = model.navigator {
            ReadiumNavigatorContainer(controller: navigator)
                .ignoresSafeArea()
                .overlay(alignment: .top) { if !model.chromeHidden { topBar } }
                .overlay(alignment: .bottom) { if !model.chromeHidden { controlBar } }
                .animation(.easeInOut(duration: 0.2), value: model.chromeHidden)
                .toolbar(model.chromeHidden ? .hidden : .visible, for: .navigationBar)
                .sheet(isPresented: $showChapters) { chapterSheet }
        }
    }

    private var topBar: some View {
        VStack(spacing: 2) {
            Text(model.title).font(.headline).lineLimit(1)
            if let progress = model.totalProgression {
                Text("\(Int((progress * 100).rounded()))% • \(model.currentLocator?.title ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var controlBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button { model.goPrevious() } label: {
                    Image(systemName: "chevron.left").frame(maxWidth: .infinity)
                }
                Button { showChapters = true } label: {
                    Image(systemName: "list.bullet").frame(maxWidth: .infinity)
                }
                Button { model.goNext() } label: {
                    Image(systemName: "chevron.right").frame(maxWidth: .infinity)
                }
            }
            .font(.title3)

            HStack(spacing: 16) {
                Toggle("Scroll", isOn: Binding(get: { model.scroll }, set: { model.scroll = $0 }))
                    .toggleStyle(.button)

                Picker("Theme", selection: Binding(get: { model.theme }, set: { model.theme = $0 })) {
                    Text("Light").tag(ReadiumNavigator.Theme.light)
                    Text("Sepia").tag(ReadiumNavigator.Theme.sepia)
                    Text("Dark").tag(ReadiumNavigator.Theme.dark)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Image(systemName: "textformat.size.smaller")
                Slider(value: Binding(get: { model.fontSize }, set: { model.fontSize = $0 }),
                       in: 0.7 ... 2.5)
                Image(systemName: "textformat.size.larger")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var chapterSheet: some View {
        NavigationStack {
            List(Array(model.toc.enumerated()), id: \.offset) { _, link in
                Button {
                    model.go(to: link)
                    showChapters = false
                } label: {
                    Text(link.title ?? link.href).foregroundStyle(.primary)
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showChapters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Placeholder

    private func placeholder(systemImage: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Choose EPUB…") { importing = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
#endif
