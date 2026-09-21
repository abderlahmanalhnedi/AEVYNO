import DesignSystem
import Domain
import Library
import Playback
import SwiftUI

private enum TVLibraryFocusTarget: Hashable {
  case continueWatching(String)
  case favorite(String)
  case item(String)
  case loadMore
}

struct TVProductionLibraryView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.resetFocus) private var resetFocus
  @Namespace private var libraryFocusScope
  @State private var viewModel: ProductionLibraryViewModel
  @FocusState private var focusedTarget: TVLibraryFocusTarget?
  @State private var rememberedItemID: String?
  @State private var openedFavoriteID: String?
  @State private var selectedItem: LibraryItemPresentation?
  @State private var continueWatchingViewModel: ContinueWatchingViewModel
  @State private var favoritesViewModel: FavoritesViewModel
  @State private var continueWatchingSession: PlaybackSession?
  @State private var resumedContinueWatchingID: String?
  @State private var showsSources = false

  private let artworkPipeline: ArtworkImagePipeline
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory
  private let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  private let continueWatchingServiceFactory: ContinueWatchingViewModel.ServiceFactory
  private let favoritesServiceFactory: FavoritesViewModel.ServiceFactory
  private let playbackEngineFactory: PlaybackDetailViewModel.EngineFactory
  private let epgServiceFactory: EPGNowNextViewModel.ServiceFactory

  init(
    viewModel: ProductionLibraryViewModel,
    artworkPipeline: ArtworkImagePipeline,
    sourceServiceFactory: @escaping SourceManagementViewModel.ServiceFactory,
    playbackServiceFactory: @escaping PlaybackDetailViewModel.ServiceFactory,
    continueWatchingServiceFactory: @escaping ContinueWatchingViewModel.ServiceFactory,
    favoritesServiceFactory: @escaping FavoritesViewModel.ServiceFactory,
    playbackEngineFactory: @escaping PlaybackDetailViewModel.EngineFactory = {
      NativeAVPlayerEngine()
    },
    epgServiceFactory: @escaping EPGNowNextViewModel.ServiceFactory = {
      throw EPGPresentationError.unavailable
    }
  ) {
    _viewModel = State(initialValue: viewModel)
    self.artworkPipeline = artworkPipeline
    self.sourceServiceFactory = sourceServiceFactory
    self.playbackServiceFactory = playbackServiceFactory
    self.continueWatchingServiceFactory = continueWatchingServiceFactory
    self.favoritesServiceFactory = favoritesServiceFactory
    _continueWatchingViewModel = State(
      initialValue: ContinueWatchingViewModel(serviceFactory: continueWatchingServiceFactory))
    _favoritesViewModel = State(
      initialValue: FavoritesViewModel(serviceFactory: favoritesServiceFactory))
    self.playbackEngineFactory = playbackEngineFactory
    self.epgServiceFactory = epgServiceFactory
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
      .navigationDestination(
        item: $selectedItem,
        destination: { item in
          TVLibraryDetailView(
            item: item,
            artworkPipeline: artworkPipeline,
            playbackServiceFactory: playbackServiceFactory,
            playbackEngineFactory: playbackEngineFactory,
            favoritesServiceFactory: favoritesServiceFactory,
            epgServiceFactory: epgServiceFactory
          )
          .onDisappear { restoreFocusAfterDetail() }
        }
      )
      .navigationDestination(
        isPresented: $showsSources,
        destination: { TVSourcesView(serviceFactory: sourceServiceFactory) }
      )
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
    .fullScreenCover(
      item: $continueWatchingSession,
      onDismiss: {
        Task { await continueWatchingViewModel.reload() }
        if let resumedContinueWatchingID {
          focusedTarget = .continueWatching(resumedContinueWatchingID)
        }
      },
      content: { session in
        PlaybackPresentationView(session: session) {
          Task { await continueWatchingViewModel.reload() }
        }
      }
    )
  }

  private var loadConfiguredView: some View {
    navigationView
      .task { await viewModel.loadIfNeeded(protecting: rememberedItemID) }
      .task { await continueWatchingViewModel.reload() }
      .task { await favoritesViewModel.reload() }
      .onChange(of: viewModel.searchText) { _, _ in viewModel.searchTextChanged() }
  }

  private var focusConfiguredView: some View {
    loadConfiguredView
      .onChange(of: viewModel.items) { _, items in
        guard selectedItem == nil, focusedTarget != .loadMore else { return }
        if let rememberedItemID, items.contains(where: { $0.id == rememberedItemID }) {
          focusedTarget = .item(rememberedItemID)
        } else if let first = items.first {
          rememberedItemID = first.id
          focusedTarget = .item(first.id)
        }
      }
      .onChange(of: focusedTarget) { _, value in
        if case .item(let id) = value { rememberedItemID = id }
      }
  }

  private var navigationConfiguredView: some View {
    focusConfiguredView
      .onChange(of: favoritesViewModel.items) { previousItems, items in
        guard
          let activeFavoriteID = openedFavoriteID ?? focusedFavoriteID,
          !items.contains(where: { $0.id == activeFavoriteID })
        else { return }

        let replacementFavoriteID: String? = {
          guard !items.isEmpty else { return nil }
          guard
            let previousIndex = previousItems.firstIndex(where: { $0.id == activeFavoriteID })
          else {
            return items.first?.id
          }

          let replacementIndex = min(previousIndex, items.count - 1)
          return items[replacementIndex].id
        }()

        focusedTarget = nil
        openedFavoriteID = replacementFavoriteID

        if selectedItem == nil {
          if let replacementFavoriteID {
            requestFocus(.favorite(replacementFavoriteID))
            openedFavoriteID = nil
          } else {
            focusLibraryFallback()
          }
        }
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
        continueWatchingRail
        favoritesRail
        filters
        content()
      }
      .padding(.horizontal, AEVYNOSpacing.xxl)
      .padding(.vertical, AEVYNOSpacing.xl)
    }
    .scrollIndicators(.hidden)
    .focusScope(libraryFocusScope)
    .accessibilityIdentifier("library.loaded")
    .accessibilityValue(String(viewModel.items.count))
  }

  @ViewBuilder private var favoritesRail: some View {
    if !favoritesViewModel.items.isEmpty {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
        Text(AppText.favorites).aevynoTypography(.sectionTitle).foregroundStyle(
          AEVYNOColor.primaryText)
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.lg) {
            ForEach(favoritesViewModel.items) { item in
              Button {
                openedFavoriteID = item.id
                selectedItem = LibraryItemPresentation(
                  id: item.id,
                  title: item.title,
                  mediaKind: item.mediaKind,
                  sourceID: item.sourceID,
                  sourceName: "",
                  categoryID: nil,
                  categoryTitle: nil,
                  artworkURL: item.artworkURL
                )
              } label: {
                TVFavoriteCard(item: item, artworkPipeline: artworkPipeline)
              }
              .buttonStyle(TVMediaButtonStyle()).accessibilityIdentifier(
                "favorites.item.\(item.id)"
              )
              .focused($focusedTarget, equals: .favorite(item.id))
              .prefersDefaultFocus(
                focusedTarget == .favorite(item.id), in: libraryFocusScope
              )
            }
          }.focusSection()
        }.scrollIndicators(.hidden)
      }
    }
  }

  @ViewBuilder private var continueWatchingRail: some View {
    if !continueWatchingViewModel.items.isEmpty {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
        Text(AppText.continueWatching).aevynoTypography(.sectionTitle).foregroundStyle(
          AEVYNOColor.primaryText)
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.lg) {
            ForEach(continueWatchingViewModel.items) { item in
              Button {
                beginResume(item)
              } label: {
                TVContinueWatchingCard(item: item, artworkPipeline: artworkPipeline)
              }
              .buttonStyle(TVMediaButtonStyle())
              .focused($focusedTarget, equals: .continueWatching(item.id))
              .accessibilityIdentifier("continue-watching.item.\(item.id)")
              .accessibilityHint(AppText.playAccessibilityHint)
            }
          }
        }.scrollIndicators(.hidden).focusSection()
      }
    }
  }

  private func beginResume(_ item: ContinueWatchingItemPresentation) {
    resumedContinueWatchingID = item.id
    Task {
      guard let dependencies = try? await playbackServiceFactory() else { return }
      let session = PlaybackSession(
        resolver: dependencies.resolver, progressRepository: dependencies.progressRepository,
        engineFactory: playbackEngineFactory)
      session.start(mediaID: item.id, title: item.title, kind: item.mediaKind)
      continueWatchingSession = session
    }
  }

  private var focusedFavoriteID: String? {
    guard case .favorite(let id) = focusedTarget else { return nil }
    return id
  }

  private var focusedItemID: String? {
    guard case .item(let id) = focusedTarget else { return nil }
    return id
  }

  private func restoreFocusAfterDetail() {
    if let targetFavoriteID = openedFavoriteID,
      favoritesViewModel.items.contains(where: { $0.id == targetFavoriteID })
    {
      requestFocus(.favorite(targetFavoriteID))
    } else {
      focusLibraryFallback()
    }
    openedFavoriteID = nil
  }

  private func focusLibraryFallback() {
    if let id = rememberedItemID ?? viewModel.items.first?.id {
      requestFocus(.item(id))
    }
  }

  private func requestFocus(_ target: TVLibraryFocusTarget) {
    focusedTarget = nil
    Task { @MainActor in
      await Task.yield()
      focusedTarget = target
      await Task.yield()
      resetFocus(in: libraryFocusScope)
    }
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
              isFocused: focusedTarget == .item(item.id),
              artworkPipeline: artworkPipeline
            )
          }
          .buttonStyle(TVMediaButtonStyle())
          .focusEffectDisabled()
          .focused($focusedTarget, equals: .item(item.id))
          .prefersDefaultFocus(focusedTarget == .item(item.id), in: libraryFocusScope)
          .accessibilityIdentifier("library.item.\(item.id)")
          .accessibilityHint(AppText.openDetailsAccessibilityHint)
        }
      }

      if viewModel.hasMore || viewModel.isLoadingPage {
        Button(AppText.loadMore) {
          Task {
            await viewModel.loadNext(protecting: focusedItemID)
            if viewModel.hasMore { focusedTarget = .loadMore }
          }
        }
        .focused($focusedTarget, equals: .loadMore)
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
  @State private var playbackViewModel: PlaybackDetailViewModel
  @State private var playbackSession: PlaybackSession?
  @State private var favoritesViewModel: FavoritesViewModel
  @State private var isFavorite = false
  @State private var epgViewModel: EPGNowNextViewModel

  init(
    item: LibraryItemPresentation,
    artworkPipeline: ArtworkImagePipeline,
    playbackServiceFactory: @escaping PlaybackDetailViewModel.ServiceFactory,
    playbackEngineFactory: @escaping PlaybackDetailViewModel.EngineFactory,
    favoritesServiceFactory: @escaping FavoritesViewModel.ServiceFactory,
    epgServiceFactory: @escaping EPGNowNextViewModel.ServiceFactory
  ) {
    self.item = item
    self.artworkPipeline = artworkPipeline
    _playbackViewModel = State(
      initialValue: PlaybackDetailViewModel(
        item: item,
        serviceFactory: playbackServiceFactory,
        engineFactory: playbackEngineFactory
      ))
    _favoritesViewModel = State(
      initialValue: FavoritesViewModel(serviceFactory: favoritesServiceFactory))
    _epgViewModel = State(
      initialValue: EPGNowNextViewModel(itemID: item.id, serviceFactory: epgServiceFactory))
  }

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
        nowNext
        playbackActions
        Button(isFavorite ? AppText.removeFromFavorites : AppText.addToFavorites) {
          Task { isFavorite = await favoritesViewModel.toggle(item.id) ?? isFavorite }
        }
        .buttonStyle(.bordered).accessibilityIdentifier("library.detail.favorite")
      }
      .padding(.horizontal, 110)
      .padding(.bottom, 88)
    }
    .task { await playbackViewModel.load() }
    .task { isFavorite = await favoritesViewModel.isFavorite(item.id) }
    .task { await epgViewModel.load() }
    .fullScreenCover(
      item: $playbackSession,
      onDismiss: {
        Task { await playbackViewModel.load() }
      },
      content: { session in
        PlaybackPresentationView(session: session)
      }
    )
  }

  @ViewBuilder private var nowNext: some View {
    if item.mediaKind == .live, let now = epgViewModel.presentation.now {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
        Text(AppText.nowProgramme(now.title)).aevynoTypography(.status)
        if let next = epgViewModel.presentation.next {
          Text(AppText.nextProgramme(next.title))
            .aevynoTypography(.metadata).foregroundStyle(AEVYNOColor.secondaryText)
        }
      }
      .accessibilityIdentifier("library.detail.now-next")
    }
  }

  @ViewBuilder
  private var playbackActions: some View {
    switch playbackViewModel.state {
    case .loading:
      ProgressView(AppText.playbackPreparing)
        .accessibilityIdentifier("library.detail.playback-loading")
    case .play:
      Button(AppText.play) { beginPlayback(startOver: false) }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("library.detail.play")
        .accessibilityHint(AppText.playAccessibilityHint)
    case .resume(let position):
      HStack(spacing: AEVYNOSpacing.sm) {
        Button(AppText.resumeFrom(position)) { beginPlayback(startOver: false) }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("library.detail.resume")
        Button(AppText.startOver) { beginPlayback(startOver: true) }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("library.detail.start-over")
      }
    case .unavailable(let failure):
      Text(AppText.playbackFailureMessage(failure))
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .padding(.horizontal, AEVYNOSpacing.md)
        .padding(.vertical, AEVYNOSpacing.sm)
        .background(AEVYNOColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card))
        .accessibilityIdentifier("library.detail.playback-unavailable")
    }
  }

  private func beginPlayback(startOver: Bool) {
    playbackSession = playbackViewModel.makeSession(startOver: startOver)
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
