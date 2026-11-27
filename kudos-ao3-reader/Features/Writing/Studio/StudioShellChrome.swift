import SwiftUI

/// Chrome components owned by the Writing Studio shell (`Studio-Overview`, `Studio-Offline`):
/// the four-part section bar, the signed-out account-required panel, and the pseud switcher.

/// Four-part segmented bar for Writing Studio: Overview · Documents · Comments · Stats.
/// Reflows into a 2×2 grid at accessibility Dynamic Type sizes so no label clips.
struct StudioSectionBar: View {
    @Binding var selection: StudioSection
    let isSignedIn: Bool
    let unreadCommentCount: Int

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(StudioSection.allCases) { section in
                        segmentButton(section)
                    }
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(StudioSection.allCases) { section in
                        segmentButton(section)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.appTheme.glassFill(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.appTheme.glassStroke(0.14), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Writing sections")
    }

    private func segmentButton(_ section: StudioSection) -> some View {
        let isSelected = selection == section
        let isLocked = !isSignedIn && section.requiresAccount
        let showsUnreadDot = isSignedIn && section == .comments && unreadCommentCount > 0
        let spokenLabel = accessibilityLabel(
            for: section,
            isLocked: isLocked,
            showsUnreadDot: showsUnreadDot
        )

        return Button {
            withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                selection = section
            }
        } label: {
            HStack(spacing: 4) {
                Text(section.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if showsUnreadDot {
                    Circle()
                        .fill(.accentFill)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                } else if isLocked {
                    Image(systemName: "lock")
                        .font(.caption2.weight(.medium))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(segmentForeground(isSelected: isSelected, isLocked: isLocked))
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selectedSegmentFill)
                        .shadow(
                            color: theme.appTheme.cardShadow.color,
                            radius: theme.appTheme.cardShadow.radius > 0 ? 2 : 0,
                            y: theme.appTheme.cardShadow.radius > 0 ? 1 : 0
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedSegmentFill: Color {
        theme.appTheme == .light ? Color.white : theme.appTheme.cardSurface
    }

    private func segmentForeground(isSelected: Bool, isLocked: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.primary) }
        if isLocked { return AnyShapeStyle(.secondaryInk) }
        return AnyShapeStyle(Color.primary.opacity(0.78))
    }

    private func accessibilityLabel(
        for section: StudioSection,
        isLocked: Bool,
        showsUnreadDot: Bool
    ) -> String {
        if isLocked {
            return "\(section.title), needs an AO3 account"
        }
        if showsUnreadDot {
            return "\(section.title), \(unreadCommentCount.formatted()) unread"
        }
        return section.title
    }
}

/// Account-required panel shown for Comments and Stats when signed out (`Studio-Offline`).
struct StudioSignedOutSectionPanel: View {
    let section: StudioSection
    let onSignIn: () -> Void
    let onBackToOverview: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(theme.appTheme.glassFill(0.12))
                            .frame(width: 60, height: 60)
                        Image(systemName: section.signedOutSymbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.accentInk)
                    }
                    .accessibilityHidden(true)

                    Text(section.signedOutHeadline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(section.signedOutDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "Your documents, editor, word counts and daily goal keep working on this "
                            + "\(ThisDevice.name)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(action: onSignIn) {
                        Text("Log In to AO3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kudosPrimaryConfirm)
                    .padding(.top, 4)
                    .accessibilityLabel("Log In to AO3")

                    Button(action: onBackToOverview) {
                        Text("Back to Overview")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kudosSecondary)
                    .accessibilityLabel("Back to Overview")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .subjectPanel()
            }
            .padding(.horizontal, SubjectMetrics.accountGutter)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }
}

/// Pseud switcher under the Writing title when signed in (`Studio-Overview.dc.html`).
struct StudioPseudMenu: View {
    var profileModel: AO3AuthorProfileModel?
    @Binding var postingPseudName: String?

    @Environment(AO3AuthService.self) private var auth

    private var activePseudLabel: String {
        postingPseudName ?? auth.username ?? "Account Default"
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button {
                    setPseud(nil)
                } label: {
                    Label(
                        auth.username ?? "Account Default",
                        systemImage: postingPseudName == nil ? "checkmark" : "person"
                    )
                }
                ForEach(availablePseuds) { pseud in
                    Button {
                        setPseud(pseud.name)
                    } label: {
                        Label(
                            pseud.name,
                            systemImage: postingPseudName == pseud.name ? "checkmark" : "person"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Posting as")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                    Text(activePseudLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondaryInk)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Posting as \(activePseudLabel). Change pseud")
            Spacer(minLength: 0)
        }
    }

    private var availablePseuds: [AO3AuthorPseud] {
        var pseuds = profileModel?.header?.pseuds ?? []
        if let selected = postingPseudName,
           !pseuds.contains(where: { $0.name.localizedCaseInsensitiveCompare(selected) == .orderedSame }),
           let username = auth.username,
           let route = AO3AuthorRoute(username: username, pseud: selected) {
            pseuds.append(AO3AuthorPseud(name: selected, route: route, avatarURL: nil))
        }
        return pseuds
    }

    private func setPseud(_ name: String?) {
        postingPseudName = name
        auth.setPreferredPostingPseudName(name)
    }
}
