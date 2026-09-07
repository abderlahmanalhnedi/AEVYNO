import DesignSystem
import Domain
import Library
import SwiftUI

struct TVHomeView: View {
    @State private var viewModel: HomeViewModel
    @FocusState private var focusedItemID: MediaItem.ID?
    @State private var selectedItem: MediaItem?

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            AEVYNOColor.background.ignoresSafeArea()

            content
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.state) { _, state in
            guard focusedItemID == nil,
                  case let .loaded(sections) = state,
                  let firstItem = sections.first?.items.first else {
                return
            }
            focusedItemID = firstItem.id
        }
        .alert(item: $selectedItem) { item in
            Alert(
                title: Text(item.title),
                message: Text("This card demonstrates the Phase 0 interface. Playback is intentionally not included."),
                dismissButton: .default(Text("Done"))
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            TVHomeLoadingView()
        case let .loaded(sections):
            loadedContent(sections)
        case .empty:
            StatusPanel(
                symbolName: "rectangle.stack.badge.plus",
                title: "A quiet start",
                message: "There is no preview content to show. Source setup belongs to a later phase."
            )
            .accessibilityIdentifier("home.empty")
        case let .failure(error):
            StatusPanel(
                symbolName: "arrow.clockwise.circle",
                title: error.title,
                message: error.message,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.reload() }
            }
            .accessibilityIdentifier("home.error")
        }
    }

    private func loadedContent(_ sections: [HomeSection]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.xl) {
                header

                ForEach(sections) { section in
                    TVMediaRail(
                        section: section,
                        focusedItemID: $focusedItemID,
                        onSelect: { selectedItem = $0 }
                    )
                }
            }
            .padding(.horizontal, AEVYNOSpacing.xxl)
            .padding(.vertical, AEVYNOSpacing.xl)
        }
        .accessibilityIdentifier("home.loaded")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
            Text("AEVYNO")
                .aevynoTypography(.hero)
                .foregroundStyle(AEVYNOColor.primaryText)

            Text("A calm place for your media")
                .aevynoTypography(.status)
                .foregroundStyle(AEVYNOColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TVMediaRail: View {
    let section: HomeSection
    let focusedItemID: FocusState<MediaItem.ID?>.Binding
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
            Text(section.title)
                .aevynoTypography(.sectionTitle)
                .foregroundStyle(AEVYNOColor.primaryText)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(spacing: AEVYNOSpacing.lg) {
                    ForEach(section.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            TVMediaCard(
                                item: item,
                                isFocused: focusedItemID.wrappedValue == item.id
                            )
                        }
                        .buttonStyle(TVMediaButtonStyle())
                        .focusEffectDisabled()
                        .focused(focusedItemID, equals: item.id)
                        .accessibilityIdentifier("home.card.\(item.id.rawValue)")
                        .accessibilityHint("Opens a Phase 0 preview message")
                    }
                }
                .padding(.vertical, AEVYNOSpacing.sm)
            }
            .scrollIndicators(.hidden)
            .focusSection()
        }
    }
}
