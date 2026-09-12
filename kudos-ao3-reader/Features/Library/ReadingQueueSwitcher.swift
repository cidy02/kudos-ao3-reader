import SwiftUI

/// `ReadingQueueBrowserView`'s Safari-style queue switcher — the compact-layout
/// bottom bar, its "New Queue" sheet, and the switcher sheet's own row list.
/// Split into its own file (not its own type) purely to keep
/// `ReadingQueueBrowser.swift` under this repo's file-length gate; every member
/// here still belongs to `ReadingQueueBrowserView` and reads its `@State`
/// directly, the same as if this were still inline.
extension ReadingQueueBrowserView {
    /// The switcher used to be a hand-drawn floating overlay, positioned by the app
    /// itself with no relationship to the system's own tab-bar-hide animation — two
    /// timing-based fix attempts (see git history) couldn't make that combination
    /// reliably seamless, because the two animations were never actually coordinated,
    /// just separately timed to *look* right. Library's Select-mode bottom bar
    /// (`ToolbarItemGroup(placement: .bottomBar)` in `LibraryView.manageToolbar`)
    /// never has this problem, because it's real toolbar content: the system treats
    /// the tab-bar-hide and the bottom-bar-show as one coordinated transition, not
    /// two independent views racing each other. This does the same thing here.
    var switcherBarContent: some View {
        Group {
            Button { showingSwitcher = true } label: {
                Image(systemName: "square.grid.2x2")
            }
            .accessibilityLabel("All Queues")
            // A direct .sheet, not .popover + .presentationCompactAdaptation(.sheet):
            // this bar only ever renders in compactLayout (iPhone) — regularLayout
            // (iPad/Mac) is a completely different sidebar List and never shows
            // this switcher at all — so there's no real popover behavior being
            // adapted from. Going through the popover-adaptation path was the
            // likely cause of two earlier attempts' clipped top chrome — see
            // switcherList's own doc comment for the full reasoning and the
            // working reference patterns (this file's newQueueSheet,
            // CommentsView's chapter picker) this now matches.
            .sheet(isPresented: $showingSwitcher) {
                switcherList
            }

            Spacer()

            Button { showingSwitcher = true } label: {
                HStack(spacing: 6) {
                    queueGlyph(selectedQueue)
                    Text(selectedQueue?.displayName ?? "Reading Queues")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            }
            .accessibilityLabel("Switch Reading Queue")
            .accessibilityValue(selectedQueue?.displayName ?? "No queue selected")

            Spacer()

            Button {
                newQueueName = ""
                showingNewQueue = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Queue")
        }
    }

    var newQueueSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newQueueName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            .navigationTitle("New Queue")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newQueueName = ""
                        showingNewQueue = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createQueue() }
                        .disabled(newQueueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Switcher list

    /// Same shape as this file's own `newQueueSheet` and CommentsView's chapter
    /// picker: a real `NavigationStack` + title, not a bare `List` handed to
    /// `.popover(...).presentationCompactAdaptation(.sheet)`, which is what
    /// clipped the sheet's top chrome in two earlier attempts here.
    ///
    /// Plain rows, not `.cardRow()`/`.cardList()`: the reader's own Contents/
    /// Bookmarks/Highlights sheet (`ReaderContentsSheet.chapterList`) — the
    /// reference this is matching — is a flat `.listStyle(.plain)` list with
    /// default hairline separators, not floating rounded cards.
    ///
    /// No `.appThemedRows()`/`.appThemedScroll()`, and no
    /// `.presentationBackground` override — three straight attempts at the
    /// latter (unset, `.regularMaterial`, `.ultraThinMaterial`) all looked
    /// equally opaque on device, which was the tell: the material was never
    /// the actual variable. `ReaderTheme.appBaseBackground`/
    /// `appElevatedBackground` (`Features/Reader/ReaderStyle.swift`) are `nil`
    /// **only** for `.light` — for Sepia/Dark/OLED they're real opaque
    /// colors, so `.appThemedScroll()`/`.appThemedRows()` were painting a
    /// solid `.background()`/`.listRowBackground()` over the whole list on
    /// this device's Dark/OLED theme, sitting on top of and completely
    /// masking whatever `.presentationBackground` material the sheet
    /// declared — confirmed root cause (root-caused via Gemini after three
    /// failed material-only attempts by hand). The reader sheet never
    /// applies these modifiers either, so dropping them here — Sepia
    /// included — matches the reference exactly rather than approximating
    /// it, and lets the system's own default sheet translucency show through
    /// unobstructed, the same as `readerSheet`.
    private var switcherList: some View {
        NavigationStack {
            List {
                ForEach(orderedQueues) { queue in
                    queueRow(queue)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Reading Queues")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showingSwitcher = false } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    func queueRow(_ queue: ReadingQueue) -> some View {
        let workCount = ReadingQueueService.orderedWorks(in: queue).count
        let isSelected = queue.id == selectedQueue?.id
        return Button { select(queue) } label: {
            HStack(spacing: 10) {
                queueGlyph(queue)
                Text(queue.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(workCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(workCount) work\(workCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func queueGlyph(_ queue: ReadingQueue?) -> some View {
        if let queue, queue.kind != .savedForLater {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: CoverArt.hue(for: queue.displayName)))
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: WorkActionLabels.savedForLaterSymbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
