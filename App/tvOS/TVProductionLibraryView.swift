import DesignSystem
import Domain
import Library
import SwiftUI

struct TVProductionLibraryView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var viewModel: ProductionLibraryViewModel
  @FocusState private var focusedItemID: String?
  @FocusState private var isLoadMoreFocused: Bool
  @State private var rememberedItemID: String?
  @State private var selectedItem: LibraryItemPresentation?
  @State private var showsSources = false

  private let artworkPipeline: ArtworkImagePipeline
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory

  init(
    viewModel: ProductionLibraryViewModel,
    artworkPipeline: ArtworkImagePipeline,
    sourceServiceFactory: @escaping SourceManagementViewModel.ServiceFactory
  ) {
    _viewModel = State(initialValue: viewModel)
    self.artworkPipeline = artworkPipeline
    self.sourceServiceFactory = sourceServiceFactory
  }

  var body: some View {
    lifecycleConfiguredView
  }

  private var navigationView: some View {
    NavigationStack {
      ZStack {
        AEVYNOColor.background.ignoresSafeArea()
        content
      }
      .navigationDestination(item: $selectedItem) { item in
        TVLibraryDetailView(item: item, artworkPipeline: artworkPipeline)
      }
      .navigationDestination(isPresented: $showsSources) {
        TVSourcesView(serviceFactory: sourceServiceFactory)
      }
      .searchable(
        text: $viewModel.searchText,
        placement: .automatic,
        prompt: AppText.librarySearchPrompt
      )
      .onSubmit(of: .search) {
        viewModel.selectScope(.search)
        viewModel.submitSearch()
      }
    }
    .preferredColorScheme(.dark)
  }

  private var loadConfiguredView: some View {
    navigationView
      .task { await viewModel.loadIfNeeded(protecting: rememberedItemID) }
      .onChange(of: viewModel.searchText) { _, _ in viewModel.searchTextChanged() }
  }

  private var focusConfiguredView: some View {
    loadConfiguredView
      .onChange(of: viewModel.items) { _, items in
        guard selectedItem == nil, !isLoadMoreFocused else { return }
        if let rememberedItemID, items.contains(where: { $0.id == rememberedItemID }) {
          focusedItemID = rememberedItemID
        } else if let first = items.first {
          rememberedItemID = first.id
          focusedItemID = first.id
        }
      }
      .onChange(of: focusedItemID) { _, value in
        if let value { rememberedItemID = value }
      }
  }

  private var navigationConfiguredView: some View {
    focusConfiguredView
      .onChange(of: selectedItem?.id) { (previous: String?, current: String?) in
        if previous != nil, current == nil { focusedItemID = rememberedItemID }
      }
      .onChange(of: showsSources) { previous, current in
        if previous, !current {
          Task { await viewModel.reloadAll(protecting: rememberedItemID) }
        }
      }
  }

  private var lifecycleConfiguredView: some View {
    navigationConfiguredView
      .onChange(of: scenePhase) { _, phase in
        if phase == ScenePhase.active {
          Task { await viewModel.reloadAll(protecting: rememberedItemID) }
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.screenState {
    case .loading:
      TVHomeLoadingView()
    case .noSources:
      status(
        symbol: "rectangle.stack.badge.plus",
        title: AppText.libraryNoSourcesTitle,
        message: AppText.libraryNoSourcesMessage,
        action: AppText.addSource,
        identifier: "library.add-source"
      ) { showsSources = true }
    case .noCatalog:
      status(
        symbol: "arrow.triangle.2.circlepath",
        title: AppText.libraryNoCatalogTitle,
        message: AppText.libraryNoCatalogMessage,
        action: AppText.refreshLibrary,
        identifier: "library.manage-sources"
      ) { showsSources = true }
    case .failure:
      status(
        symbol: "exclamationmark.arrow.triangle.2.circlepath",
        title: AppText.libraryUnavailableTitle,
        message: AppText.libraryUnavailableMessage,
        action: AppText.retry,
        identifier: "library.retry"
      ) { viewModel.retry(protecting: rememberedItemID) }
    case .searchPrompt:
      libraryChrome {
        TVLibraryMessage(
          symbol: "magnifyingglass",
          title: AppText.librarySearchPromptTitle,
          message: AppText.librarySearchPromptMessage
        )
        .accessibilityIdentifier("library.search-prompt")
      }
    case .noResults:
      libraryChrome {
        TVLibraryMessage(
          symbol: "magnifyingglass",
          title: AppText.libraryNoResultsTitle,
          message: AppText.libraryNoResultsMessage
        )
        .accessibilityIdentifier("library.no-results")
      }
    case .empty:
      libraryChrome {
        TVLibraryMessage(
          symbol: "rectangle.stack",
          title: AppText.libraryEmptyTitle,
          message: AppText.libraryEmptyMessage
        )
        .accessibilityIdentifier("library.empty")
      }
    case .content:
      libraryChrome { itemGrid }
    }
  }

  private func libraryChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
        header
        filters
        content()
      }
      .padding(.horizontal, AEVYNOSpacing.xxl)
      .padding(.vertical, AEVYNOSpacing.xl)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("library.loaded")
    .accessibilityValue(String(viewModel.items.count))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Text(AppText.libraryTitle)
        .aevynoTypography(.hero)
        .foregroundStyle(AEVYNOColor.primaryText)
        .accessibilityAddTraits(.isHeader)

      HStack(spacing: AEVYNOSpacing.sm) {
        ForEach(LibraryBrowseScope.allCases, id: \.self) { scope in
          Button(AppText.libraryScope(scope)) {
            viewModel.selectScope(scope, protecting: rememberedItemID)
          }
          .buttonStyle(.bordered)
          .tint(scope == viewModel.scope ? AEVYNOColor.accent : AEVYNOColor.surface)
          .accessibilityIdentifier("library.scope.\(scope.rawValue)")
        }
        Button(AppText.sources) { showsSources = true }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("library.sources")
      }
    }
  }

  @ViewBuilder
  private var filters: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      if let context = viewModel.context, !context.sources.isEmpty {
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.sm) {
            Button(AppText.allSources) { viewModel.selectSource(nil) }
              .buttonStyle(.bordered)
              .tint(
                viewModel.selectedSourceID == nil ? AEVYNOColor.accent : AEVYNOColor.surface
              )
              .accessibilityIdentifier("library.source.all")
              .accessibilityHint(AppText.sourceFilterAccessibilityHint)
            ForEach(context.sources) { source in
              Button(source.name) { viewModel.selectSource(source.id) }
                .buttonStyle(.bordered)
                .tint(
                  source.id == viewModel.selectedSourceID
                    ? AEVYNOColor.accent : AEVYNOColor.surface
                )
                .accessibilityHint(AppText.sourceFilterAccessibilityHint)
            }
          }
        }
        .scrollIndicators(.hidden)
        .focusSection()
      }

      if !viewModel.categories.isEmpty {
        Text(AppText.categories)
          .aevynoTypography(.sectionTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.sm) {
            if viewModel.selectedCategory != nil {
              Button(AppText.allCategories) { viewModel.selectCategory(nil) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.category.all")
            }
            ForEach(viewModel.categories) { category in
              Button {
                viewModel.selectCategory(category, protecting: rememberedItemID)
              } label: {
                Text("\(category.title)  ·  \(category.itemCount)")
              }
              .buttonStyle(.bordered)
              .tint(
                category.id == viewModel.selectedCategory?.id
                  ? AEVYNOColor.accent : AEVYNOColor.surface
              )
              .accessibilityIdentifier("library.category.\(category.id.rawValue)")
            }
          }
        }
        .scrollIndicators(.hidden)
        .focusSection()
      }
    }
  }

  private var itemGrid: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 260), spacing: AEVYNOSpacing.lg)],
        alignment: .leading,
        spacing: AEVYNOSpacing.lg
      ) {
        ForEach(viewModel.items) { item in
          Button {
            rememberedItemID = item.id
            selectedItem = item
          } label: {
            TVLibraryCard(
              item: item,
              isFocused: focusedItemID == item.id,
              artworkPipeline: artworkPipeline
            )
          }
          .buttonStyle(TVMediaButtonStyle())
          .focusEffectDisabled()
          .focused($focusedItemID, equals: item.id)
          .accessibilityIdentifier("library.item.\(item.id)")
          .accessibilityHint(AppText.openDetailsAccessibilityHint)
        }
      }

      if viewModel.hasMore || viewModel.isLoadingPage {
        Button(AppText.loadMore) {
          Task {
            await viewModel.loadNext(protecting: focusedItemID)
            if viewModel.hasMore { isLoadMoreFocused = true }
          }
        }
        .focused($isLoadMoreFocused)
        .accessibilityIdentifier("library.load-more")
      }
    }
    .focusSection()
  }

  private func status(
    symbol: String,
    title: String,
    message: String,
    action: String,
    identifier: String,
    perform: @escaping () -> Void
  ) -> some View {
    TVLibraryMessage(
      symbol: symbol,
      title: title,
      message: message,
      action: action,
      actionIdentifier: identifier,
      perform: perform
    )
  }

}

private struct TVLibraryCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let item: LibraryItemPresentation
  let isFocused: Bool
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      RemoteArtworkImageView(
        itemID: item.id,
        artworkURL: item.artworkURL,
        placeholderKind: placeholderKind,
        pixelWidth: 560,
        pixelHeight: 336,
        pipeline: artworkPipeline
      )
      .frame(height: 168)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))

      Text(item.title)
        .aevynoTypography(.cardTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
        .lineLimit(1)
      Text(AppText.libraryItemMetadata(item))
        .aevynoTypography(.metadata)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .lineLimit(1)
    }
    .frame(width: 280, alignment: .leading)
    .padding(AEVYNOSpacing.sm)
    .aevynoCardSurface()
    .aevynoTVFocusTreatment(isFocused: isFocused, reduceMotion: reduceMotion)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.title)
    .accessibilityValue(AppText.libraryItemMetadata(item))
  }

  private var placeholderKind: CatalogArtworkPlaceholderKind {
    switch item.mediaKind {
    case .vod: .movie
    case .series: .series
    case .live: .live
    case .unspecified: .playlist
    }
  }
}

private struct TVLibraryMessage: View {
  @FocusState private var isActionFocused: Bool
  let symbol: String
  let title: String
  let message: String
  var action: String?
  var actionIdentifier: String?
  var perform: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Image(systemName: symbol)
        .font(.system(size: 42, weight: .semibold))
        .foregroundStyle(AEVYNOColor.accent)
        .accessibilityHidden(true)
      Text(title).aevynoTypography(.sectionTitle).foregroundStyle(AEVYNOColor.primaryText)
      Text(message).aevynoTypography(.status).foregroundStyle(AEVYNOColor.secondaryText)
      if let action, let perform {
        Button(action, action: perform)
          .buttonStyle(.borderedProminent)
          .focused($isActionFocused)
          .accessibilityIdentifier(actionIdentifier ?? "library.message-action")
      }
    }
    .padding(AEVYNOSpacing.xl)
    .frame(maxWidth: 760, alignment: .leading)
    .background(AEVYNOColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
    .task {
      if action != nil { isActionFocused = true }
    }
  }
}

private struct TVLibraryDetailView: View {
  let item: LibraryItemPresentation
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AEVYNOColor.background.ignoresSafeArea()
      RemoteArtworkImageView(
        itemID: item.id,
        artworkURL: item.artworkURL,
        placeholderKind: placeholderKind,
        pixelWidth: 2_048,
        pixelHeight: 1_152,
        pipeline: artworkPipeline
      )
      .ignoresSafeArea()
      .accessibilityHidden(true)
      LinearGradient(
        colors: [.clear, AEVYNOColor.background.opacity(0.88), AEVYNOColor.background],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        Text(AppText.libraryKind(item.mediaKind))
          .aevynoTypography(.eyebrow)
          .foregroundStyle(AEVYNOColor.accent)
        Text(item.title)
          .aevynoTypography(.detailTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
          .accessibilityIdentifier("library.detail.title")
        Text(AppText.libraryItemMetadata(item))
          .aevynoTypography(.metadata)
          .foregroundStyle(AEVYNOColor.secondaryText)
        Text(AppText.playbackUnavailable)
          .aevynoTypography(.status)
          .foregroundStyle(AEVYNOColor.secondaryText)
          .padding(.horizontal, AEVYNOSpacing.md)
          .padding(.vertical, AEVYNOSpacing.sm)
          .background(AEVYNOColor.surface)
          .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card))
          .accessibilityIdentifier("library.detail.playback-unavailable")
          .accessibilityHint(AppText.playbackUnavailableHint)
      }
      .padding(.horizontal, 110)
      .padding(.bottom, 88)
    }
  }

  private var placeholderKind: CatalogArtworkPlaceholderKind {
    switch item.mediaKind {
    case .vod: .movie
    case .series: .series
    case .live: .live
    case .unspecified: .playlist
    }
  }
}
