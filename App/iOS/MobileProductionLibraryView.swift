import DesignSystem
import Domain
import Library
import Playback
import SwiftUI

struct MobileProductionLibraryView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var viewModel: ProductionLibraryViewModel
  @State private var selectedItem: LibraryItemPresentation?
  @State private var continueWatchingViewModel: ContinueWatchingViewModel
  @State private var favoritesViewModel: FavoritesViewModel
  @State private var continueWatchingSession: PlaybackSession?
  @State private var showsSources = false

  private let artworkPipeline: ArtworkImagePipeline
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory
  private let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  private let continueWatchingServiceFactory: ContinueWatchingViewModel.ServiceFactory
  private let favoritesServiceFactory: FavoritesViewModel.ServiceFactory
  private let epgServiceFactory: EPGNowNextViewModel.ServiceFactory

  init(
    viewModel: ProductionLibraryViewModel,
    artworkPipeline: ArtworkImagePipeline,
    sourceServiceFactory: @escaping SourceManagementViewModel.ServiceFactory,
    playbackServiceFactory: @escaping PlaybackDetailViewModel.ServiceFactory,
    continueWatchingServiceFactory: @escaping ContinueWatchingViewModel.ServiceFactory,
    favoritesServiceFactory: @escaping FavoritesViewModel.ServiceFactory,
    epgServiceFactory: @escaping EPGNowNextViewModel.ServiceFactory = {
      throw EPGPresentationError.unavailable
    }
  ) {
    _viewModel = State(initialValue: viewModel)
    self.artworkPipeline = artworkPipeline
    self.sourceServiceFactory = sourceServiceFactory
    self.playbackServiceFactory = playbackServiceFactory
    self.continueWatchingServiceFactory = continueWatchingServiceFactory
    _continueWatchingViewModel = State(
      initialValue: ContinueWatchingViewModel(serviceFactory: continueWatchingServiceFactory))
    self.favoritesServiceFactory = favoritesServiceFactory
    _favoritesViewModel = State(
      initialValue: FavoritesViewModel(serviceFactory: favoritesServiceFactory))
    self.epgServiceFactory = epgServiceFactory
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AEVYNOColor.background.ignoresSafeArea()
        content
      }
      .navigationTitle(AppText.libraryTitle)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu(AppText.libraryScope(viewModel.scope)) {
            ForEach(LibraryBrowseScope.allCases, id: \.self) { scope in
              Button(AppText.libraryScope(scope)) { viewModel.selectScope(scope) }
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(AppText.sources, systemImage: "externaldrive") { showsSources = true }
        }
      }
      .navigationDestination(item: $selectedItem) { item in
        MobileLibraryDetailView(
          item: item,
          artworkPipeline: artworkPipeline,
          playbackServiceFactory: playbackServiceFactory,
          favoritesServiceFactory: favoritesServiceFactory,
          epgServiceFactory: epgServiceFactory
        )
      }
      .sheet(isPresented: $showsSources) {
        MobileLibrarySourcesView(
          viewModel: SourceManagementViewModel(serviceFactory: sourceServiceFactory)
        )
      }
      .searchable(text: $viewModel.searchText, prompt: AppText.librarySearchPrompt)
      .onSubmit(of: .search) {
        viewModel.selectScope(.search)
        viewModel.submitSearch()
      }
    }
    .preferredColorScheme(.dark)
    .task { await viewModel.loadIfNeeded() }
    .task { await continueWatchingViewModel.reload() }
    .task { await favoritesViewModel.reload() }
    .fullScreenCover(
      item: $continueWatchingSession,
      onDismiss: {
        Task { await continueWatchingViewModel.reload() }
      }
    ) { session in
      PlaybackPresentationView(session: session) {
        Task { await continueWatchingViewModel.reload() }
      }
    }
    .onChange(of: viewModel.searchText) { _, _ in viewModel.searchTextChanged() }
    .onChange(of: showsSources) { previous, current in
      if previous, !current { Task { await viewModel.reloadAll() } }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await viewModel.reloadAll() }
        Task { await continueWatchingViewModel.reload() }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.screenState {
    case .loading:
      ProgressView().tint(AEVYNOColor.accent)
    case .noSources:
      mobileStatus(
        title: AppText.libraryNoSourcesTitle,
        message: AppText.libraryNoSourcesMessage,
        action: AppText.addSource
      ) { showsSources = true }
    case .noCatalog:
      mobileStatus(
        title: AppText.libraryNoCatalogTitle,
        message: AppText.libraryNoCatalogMessage,
        action: AppText.refreshLibrary
      ) { showsSources = true }
    case .failure:
      mobileStatus(
        title: AppText.libraryUnavailableTitle,
        message: AppText.libraryUnavailableMessage,
        action: AppText.retry
      ) { viewModel.retry() }
    case .searchPrompt:
      libraryShell {
        mobileStatus(
          title: AppText.librarySearchPromptTitle,
          message: AppText.librarySearchPromptMessage
        )
      }
    case .noResults:
      libraryShell {
        mobileStatus(title: AppText.libraryNoResultsTitle, message: AppText.libraryNoResultsMessage)
      }
    case .empty:
      libraryShell {
        mobileStatus(title: AppText.libraryEmptyTitle, message: AppText.libraryEmptyMessage)
      }
    case .content:
      libraryContent
    }
  }

  private var libraryContent: some View {
    libraryShell {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150), spacing: AEVYNOSpacing.sm)],
        spacing: AEVYNOSpacing.md
      ) {
        ForEach(viewModel.items) { item in
          Button {
            selectedItem = item
          } label: {
            MobileLibraryCard(item: item, artworkPipeline: artworkPipeline)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("library.item.\(item.id)")
        }
      }
      if viewModel.hasMore || viewModel.isLoadingPage {
        Button(AppText.loadMore) { Task { await viewModel.loadNext(protecting: nil) } }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.isLoadingPage)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private func libraryShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        continueWatchingRail
        favoritesRail
        filters
        content()
      }
      .padding(AEVYNOSpacing.md)
    }
  }

  @ViewBuilder private var favoritesRail: some View {
    if !favoritesViewModel.items.isEmpty {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
        Text(AppText.favorites).aevynoTypography(.sectionTitle)
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.md) {
            ForEach(favoritesViewModel.items) { item in
              Button {
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
                MobileFavoriteCard(item: item, artworkPipeline: artworkPipeline)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("favorites.item.\(item.id)")
            }
          }.padding(.vertical, AEVYNOSpacing.xs)
        }.scrollIndicators(.hidden)
      }
    }
  }

  @ViewBuilder private var continueWatchingRail: some View {
    if !continueWatchingViewModel.items.isEmpty {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
        Text(AppText.continueWatching).aevynoTypography(.sectionTitle)
        ScrollView(.horizontal) {
          LazyHStack(spacing: AEVYNOSpacing.md) {
            ForEach(continueWatchingViewModel.items) { item in
              Button {
                beginResume(item)
              } label: {
                MobileContinueWatchingCard(item: item, artworkPipeline: artworkPipeline)
              }
              .buttonStyle(.plain).accessibilityIdentifier("continue-watching.item.\(item.id)")
              .accessibilityHint(AppText.playAccessibilityHint)
            }
          }.padding(.vertical, AEVYNOSpacing.xs)
        }.scrollIndicators(.hidden)
      }
    }
  }

  private func beginResume(_ item: ContinueWatchingItemPresentation) {
    Task {
      guard let dependencies = try? await playbackServiceFactory() else { return }
      let session = PlaybackSession(
        resolver: dependencies.resolver, progressRepository: dependencies.progressRepository)
      session.start(mediaID: item.id, title: item.title, kind: item.mediaKind)
      continueWatchingSession = session
    }
  }

  @ViewBuilder
  private var filters: some View {
    if let context = viewModel.context {
      Menu {
        Button(AppText.allSources) { viewModel.selectSource(nil) }
        ForEach(context.sources) { source in
          Button(source.name) { viewModel.selectSource(source.id) }
        }
      } label: {
        Label(selectedSourceName(in: context), systemImage: "line.3.horizontal.decrease.circle")
      }
    }
    if !viewModel.categories.isEmpty {
      ScrollView(.horizontal) {
        LazyHStack {
          if viewModel.selectedCategory != nil {
            Button(AppText.allCategories) { viewModel.selectCategory(nil) }
          }
          ForEach(viewModel.categories) { category in
            Button("\(category.title) · \(category.itemCount)") {
              viewModel.selectCategory(category)
            }
          }
        }
        .buttonStyle(.bordered)
      }
      .scrollIndicators(.hidden)
    }
  }

  private func mobileStatus(
    title: String,
    message: String,
    action: String? = nil,
    perform: (() -> Void)? = nil
  ) -> some View {
    StatusPanel(
      symbolName: "rectangle.stack",
      title: title,
      message: message,
      actionTitle: action,
      action: perform
    )
    .padding(AEVYNOSpacing.md)
  }

  private func selectedSourceName(in context: ProductionLibraryContext) -> String {
    guard let selectedSourceID = viewModel.selectedSourceID,
      let source = context.sources.first(where: { $0.id == selectedSourceID })
    else { return AppText.allSources }
    return source.name
  }
}

private struct MobileLibraryCard: View {
  let item: LibraryItemPresentation
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
      RemoteArtworkImageView(
        itemID: item.id,
        artworkURL: item.artworkURL,
        placeholderKind: placeholderKind,
        pixelWidth: 400,
        pixelHeight: 240,
        pipeline: artworkPipeline
      )
      .frame(height: 105)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
      Text(item.title).aevynoTypography(.cardTitle).lineLimit(2)
      Text(AppText.libraryItemMetadata(item))
        .aevynoTypography(.metadata)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct MobileLibraryDetailView: View {
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
    favoritesServiceFactory: @escaping FavoritesViewModel.ServiceFactory,
    epgServiceFactory: @escaping EPGNowNextViewModel.ServiceFactory
  ) {
    self.item = item
    self.artworkPipeline = artworkPipeline
    _playbackViewModel = State(
      initialValue: PlaybackDetailViewModel(
        item: item,
        serviceFactory: playbackServiceFactory
      ))
    _favoritesViewModel = State(
      initialValue: FavoritesViewModel(serviceFactory: favoritesServiceFactory))
    _epgViewModel = State(
      initialValue: EPGNowNextViewModel(itemID: item.id, serviceFactory: epgServiceFactory))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        RemoteArtworkImageView(
          itemID: item.id,
          artworkURL: item.artworkURL,
          placeholderKind: placeholderKind,
          pixelWidth: 1_200,
          pixelHeight: 720,
          pipeline: artworkPipeline
        )
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.hero, style: .continuous))
        Text(item.title).aevynoTypography(.detailTitle)
        Text(AppText.libraryItemMetadata(item))
          .aevynoTypography(.metadata)
          .foregroundStyle(AEVYNOColor.secondaryText)
        nowNext
        playbackActions
        Button(isFavorite ? AppText.removeFromFavorites : AppText.addToFavorites) {
          Task { isFavorite = await favoritesViewModel.toggle(item.id) ?? isFavorite }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("library.detail.favorite")
      }
      .padding(AEVYNOSpacing.md)
    }
    .background(AEVYNOColor.background)
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
    case .play:
      Button(AppText.play) { beginPlayback(startOver: false) }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("library.detail.play")
    case .resume(let position):
      HStack {
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

private struct MobileLibrarySourcesView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: SourceManagementViewModel
  @State private var editorRoute: MobileSourceEditorRoute?

  init(viewModel: SourceManagementViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    NavigationStack {
      List {
        if viewModel.isLoading {
          ProgressView(AppText.sourcesLoading)
        } else if viewModel.loadFailed {
          VStack(spacing: AEVYNOSpacing.md) {
            ContentUnavailableView(
              AppText.sourcesUnavailable,
              systemImage: "externaldrive.badge.exclamationmark",
              description: Text(AppText.sourcesUnavailableMessage)
            )
            Button(AppText.retry) { Task { await viewModel.load() } }
          }
        } else if viewModel.sources.isEmpty {
          ContentUnavailableView(
            AppText.sourcesEmptyTitle,
            systemImage: "externaldrive.badge.plus",
            description: Text(AppText.sourcesEmptyMessage)
          )
        } else {
          ForEach(viewModel.sources) { source in
            Button {
              editorRoute = MobileSourceEditorRoute(source: source)
            } label: {
              MobileSourceRow(source: source)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sourceAccessibilityLabel(source))
            .accessibilityHint(AppText.editSourceAccessibilityHint)
          }
        }
      }
      .navigationTitle(AppText.sources)
      .navigationDestination(item: $editorRoute) { route in
        MobileSourceEditorView(
          source: route.source,
          viewModel: viewModel,
          onSaved: { editorRoute = nil },
          onDeleted: { editorRoute = nil }
        )
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button(AppText.done) { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button(AppText.addSource, systemImage: "plus") {
            editorRoute = MobileSourceEditorRoute(source: nil)
          }
          .accessibilityHint(AppText.addSourceAccessibilityHint)
        }
      }
      .task { await viewModel.load() }
    }
  }

  private func sourceAccessibilityLabel(_ source: ManagedSource) -> String {
    AppText.sourceRowAccessibilityLabel(
      name: source.configuration.displayName,
      kind: AppText.sourceKind(source.configuration.kind),
      status: source.configuration.isEnabled ? AppText.enabled : AppText.disabled
    )
  }
}

private struct MobileSourceEditorRoute: Identifiable, Hashable {
  let id = UUID()
  let source: ManagedSource?

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct MobileSourceRow: View {
  let source: ManagedSource

  var body: some View {
    HStack(spacing: AEVYNOSpacing.md) {
      Image(systemName: source.configuration.kind == .m3u ? "list.bullet.rectangle" : "server.rack")
        .foregroundStyle(AEVYNOColor.accent)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: AEVYNOSpacing.xxs) {
        Text(source.configuration.displayName).foregroundStyle(.primary)
        Text(AppText.sourceKind(source.configuration.kind))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(AppText.refreshPolicy(source.configuration.refreshPolicy))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: AEVYNOSpacing.sm)
      VStack(alignment: .trailing, spacing: AEVYNOSpacing.xxs) {
        Text(source.configuration.isEnabled ? AppText.enabled : AppText.disabled)
          .font(.caption.weight(.medium))
          .foregroundStyle(source.configuration.isEnabled ? AEVYNOColor.accent : .secondary)
        Text(AppText.lastRefreshed(source.refreshMetadata?.lastSuccessfulAt))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, AEVYNOSpacing.xs)
  }
}

private struct MobileSourceEditorView: View {
  let source: ManagedSource?
  let viewModel: SourceManagementViewModel
  let onSaved: () -> Void
  let onDeleted: () -> Void

  @State private var displayName: String
  @State private var kind: SourceKind
  @State private var endpoint: String
  @State private var epgEndpoint: String
  @State private var isEnabled: Bool
  @State private var refreshPolicy: RefreshPolicy
  @State private var replacingCredential: Bool
  @State private var username = ""
  @State private var password = ""
  @State private var showsDeleteConfirmation = false

  init(
    source: ManagedSource?,
    viewModel: SourceManagementViewModel,
    onSaved: @escaping () -> Void,
    onDeleted: @escaping () -> Void
  ) {
    self.source = source
    self.viewModel = viewModel
    self.onSaved = onSaved
    self.onDeleted = onDeleted
    _displayName = State(initialValue: source?.configuration.displayName ?? "")
    _kind = State(initialValue: source?.configuration.kind ?? .xtreamCompatible)
    _endpoint = State(initialValue: source?.configuration.endpoint?.url.absoluteString ?? "")
    _epgEndpoint = State(
      initialValue: source?.configuration.epgConfiguration?.endpoint.url.absoluteString ?? "")
    _isEnabled = State(initialValue: source?.configuration.isEnabled ?? true)
    _refreshPolicy = State(initialValue: source?.configuration.refreshPolicy ?? .manualOnly)
    _replacingCredential = State(initialValue: source == nil)
  }

  var body: some View {
    Form {
      Section {
        TextField(AppText.sourceName, text: $displayName)
          .textContentType(.name)
        Picker(AppText.sourceType, selection: $kind) {
          Text(AppText.xtreamCompatible).tag(SourceKind.xtreamCompatible)
          Text(AppText.m3uPlaylist).tag(SourceKind.m3u)
        }
        .disabled(source != nil)
        TextField(AppText.serverAddress, text: $endpoint)
          .textContentType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        if kind == .m3u {
          TextField(AppText.xmltvEndpoint, text: $epgEndpoint)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityHint(AppText.xmltvEndpointAccessibilityHint)
        }
      }

      Section(AppText.automaticRefresh) {
        Picker(AppText.automaticRefresh, selection: $refreshPolicy) {
          Text(AppText.manualOnly).tag(RefreshPolicy.manualOnly)
          Text(AppText.every6Hours).tag(RefreshPolicy.automatic(.every6Hours))
          Text(AppText.every12Hours).tag(RefreshPolicy.automatic(.every12Hours))
          Text(AppText.daily).tag(RefreshPolicy.automatic(.daily))
        }
        Text(AppText.automaticRefreshActiveExplanation).font(.footnote).foregroundStyle(.secondary)
      }

      credentialsSection
      sourceActions
      if let source { existingSourceActions(source) }
      operationStatus
    }
    .navigationTitle(source == nil ? AppText.addSource : AppText.editSource)
    .navigationBarTitleDisplayMode(.inline)
    .task { viewModel.clearOperationState() }
    .confirmationDialog(
      AppText.deleteSourceConfirmationTitle,
      isPresented: $showsDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(AppText.delete, role: .destructive) { deleteSource() }
      Button(AppText.cancel, role: .cancel) {}
    } message: {
      Text(AppText.deleteSourceConfirmationMessage)
    }
  }

  @ViewBuilder private var credentialsSection: some View {
    if kind == .xtreamCompatible {
      Section {
        if source != nil, !replacingCredential {
          LabeledContent(AppText.credentialSaved) {
            Button(AppText.replaceCredential) { replacingCredential = true }
              .accessibilityHint(AppText.replaceCredentialAccessibilityHint)
          }
        } else {
          TextField(AppText.username, text: $username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField(AppText.password, text: $password)
            .textContentType(.password)
            .accessibilityHint(AppText.passwordAccessibilityHint)
        }
      } header: {
        Text(AppText.xtreamCompatible)
      }
    } else {
      Section {
        Text(AppText.m3uQueryLimitation).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private var sourceActions: some View {
    Section {
      Button(AppText.testConnection) { testConnection() }
        .accessibilityHint(AppText.testConnectionAccessibilityHint)
      Button(AppText.save) { save() }
        .buttonStyle(.borderedProminent)
        .tint(AEVYNOColor.accent)
    }
  }

  @ViewBuilder private func existingSourceActions(_ source: ManagedSource) -> some View {
    Section {
      Toggle(
        source.configuration.isEnabled ? AppText.enabled : AppText.disabled,
        isOn: Binding(
          get: { isEnabled },
          set: { newValue in setEnabled(newValue, sourceID: source.id) }
        )
      )
      Button(AppText.refreshNow) { Task { await viewModel.refresh(id: source.id) } }
        .disabled(!isEnabled)
    }
    Section {
      Button(AppText.delete, role: .destructive) { showsDeleteConfirmation = true }
        .accessibilityHint(AppText.deleteAccessibilityHint)
    }
  }

  @ViewBuilder private var operationStatus: some View {
    if let state = viewModel.operationState {
      Section {
        Label(AppText.sourceOperationState(state), systemImage: statusSymbol(state))
          .foregroundStyle(statusColor(state))
      }
    }
  }

  private func draft() -> SourceDraft {
    let credential: SourceDraft.CredentialInput =
      if kind == .m3u { .none } else if source != nil, !replacingCredential { .unchanged } else {
        .replace(username: username, secret: password)
      }
    return SourceDraft(
      displayName: displayName,
      kind: kind,
      endpoint: endpoint,
      epgEndpoint: epgEndpoint,
      isEnabled: isEnabled,
      refreshPolicy: refreshPolicy,
      credential: credential
    )
  }

  private func testConnection() {
    let input = draft()
    Task {
      let issues = await viewModel.validate(input, editing: source?.id)
      guard issues.isEmpty else {
        viewModel.reportValidationIssues(issues)
        return
      }
      _ = await viewModel.testConnection(input, editing: source?.id)
    }
  }

  private func save() {
    let input = draft()
    Task {
      let issues = await viewModel.validate(input, editing: source?.id)
      guard issues.isEmpty else {
        viewModel.reportValidationIssues(issues)
        return
      }
      if await viewModel.save(input, editing: source?.id) {
        password = ""
        username = ""
        onSaved()
      }
    }
  }

  private func setEnabled(_ value: Bool, sourceID: SourceConfiguration.ID) {
    Task {
      await viewModel.setEnabled(value, id: sourceID)
      if !(viewModel.operationState?.isFailure ?? false) { isEnabled = value }
    }
  }

  private func deleteSource() {
    guard let source else { return }
    Task {
      if await viewModel.delete(id: source.id) {
        onDeleted()
      }
    }
  }

  private func statusSymbol(_ state: SourceOperationState) -> String {
    switch state {
    case .connectionSucceeded, .saved, .enabled, .disabled, .deleted, .refreshing(.completed):
      "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .cancelled, .refreshing(.cancelled): "xmark.circle.fill"
    default: "arrow.triangle.2.circlepath"
    }
  }

  private func statusColor(_ state: SourceOperationState) -> Color {
    if case .failed = state { return AEVYNOColor.accentWarm }
    return AEVYNOColor.accent
  }
}

extension SourceOperationState {
  fileprivate var isFailure: Bool {
    if case .failed = self { return true }
    return false
  }
}
