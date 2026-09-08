import DesignSystem
import Domain
import Library
import SwiftUI

struct TVHomeView: View {
  @State private var viewModel: HomeViewModel
  @FocusState private var focusedItemID: MediaItem.ID?
  @State private var rememberedItemID: MediaItem.ID?
  @State private var selectedItem: MediaItem?

  private let artworkPipeline: ArtworkImagePipeline

  init(viewModel: HomeViewModel, artworkPipeline: ArtworkImagePipeline) {
    _viewModel = State(initialValue: viewModel)
    self.artworkPipeline = artworkPipeline
  }

  var body: some View {
    NavigationStack {
      ZStack {
        background
        content
      }
      .navigationDestination(item: $selectedItem) { item in
        TVDetailView(item: item, artworkPipeline: artworkPipeline)
      }
    }
    .preferredColorScheme(.dark)
    .task {
      await viewModel.loadIfNeeded()
    }
    .onChange(of: viewModel.state) { _, state in
      guard focusedItemID == nil,
        case .loaded(let sections) = state,
        let firstItem = sections.first?.items.first
      else {
        return
      }
      rememberedItemID = firstItem.id
      focusedItemID = firstItem.id
    }
    .onChange(of: focusedItemID) { _, itemID in
      if let itemID { rememberedItemID = itemID }
    }
    .onChange(of: selectedItem?.id) { previousID, currentID in
      if previousID != nil, currentID == nil {
        focusedItemID = rememberedItemID
      }
    }
  }

  private var background: some View {
    ZStack {
      AEVYNOColor.background
      RadialGradient(
        colors: [AEVYNOColor.accent.opacity(0.1), .clear],
        center: UnitPoint(x: 0.82, y: 0.08),
        startRadius: 10,
        endRadius: 720
      )
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state {
    case .loading:
      TVHomeLoadingView()
    case .loaded(let sections):
      loadedContent(sections)
    case .empty:
      StatusPanel(
        symbolName: "sparkles.rectangle.stack",
        title: AppText.homeEmptyTitle,
        message: AppText.homeEmptyMessage
      )
      .accessibilityIdentifier("home.empty")
    case .failure:
      StatusPanel(
        symbolName: "arrow.clockwise.circle",
        title: AppText.homeErrorTitle,
        message: AppText.homeErrorMessage,
        actionTitle: AppText.retry,
        actionAccessibilityHint: AppText.retryAccessibilityHint
      ) {
        Task { await viewModel.reload() }
      }
      .accessibilityIdentifier("home.error")
    }
  }

  private func loadedContent(_ sections: [HomeSection]) -> some View {
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.xl) {
        TVHomeHero()

        ForEach(sections) { section in
          TVMediaRail(
            section: section,
            focusedItemID: $focusedItemID,
            artworkPipeline: artworkPipeline,
            onSelect: openDetail
          )
        }
      }
      .padding(.horizontal, AEVYNOSpacing.xxl)
      .padding(.top, AEVYNOSpacing.xl)
      .padding(.bottom, 120)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("home.loaded")
  }

  private func openDetail(_ item: MediaItem) {
    rememberedItemID = item.id
    selectedItem = item
  }
}

private struct TVMediaRail: View {
  let section: HomeSection
  let focusedItemID: FocusState<MediaItem.ID?>.Binding
  let artworkPipeline: ArtworkImagePipeline
  let onSelect: (MediaItem) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      HStack(alignment: .firstTextBaseline) {
        Text(AppText.sectionTitle(for: section.id, fallback: section.title))
          .aevynoTypography(.sectionTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
          .accessibilityAddTraits(.isHeader)

        Spacer()

        Text(AppText.itemCount(section.items.count))
          .aevynoTypography(.metadata)
          .foregroundStyle(AEVYNOColor.secondaryText)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, AEVYNOSpacing.xs)

      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: AEVYNOSpacing.lg) {
          ForEach(section.items) { item in
            Button {
              onSelect(item)
            } label: {
              TVMediaCard(
                item: item,
                family: cardFamily,
                isFocused: focusedItemID.wrappedValue == item.id,
                artworkPipeline: artworkPipeline
              )
            }
            .buttonStyle(TVMediaButtonStyle())
            .focusEffectDisabled()
            .focused(focusedItemID, equals: item.id)
            .accessibilityIdentifier("home.card.\(item.id.rawValue)")
            .accessibilityHint(AppText.openDetailsAccessibilityHint)
          }
        }
        .padding(.horizontal, AEVYNOSpacing.xs)
        .padding(.vertical, AEVYNOSpacing.sm)
      }
      .scrollIndicators(.hidden)
      .focusSection()
    }
  }

  private var cardFamily: TVMediaCardFamily {
    switch section.id {
    case .movies, .series: return .poster
    case .liveTV: return .live
    case .continueWatching, .favorites: return .landscape
    }
  }
}
