import DesignSystem
import Domain
import Library
import SwiftUI

struct MobileProductionLibraryView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var viewModel: ProductionLibraryViewModel
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
        MobileLibraryDetailView(item: item, artworkPipeline: artworkPipeline)
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
    .onChange(of: viewModel.searchText) { _, _ in viewModel.searchTextChanged() }
    .onChange(of: showsSources) { previous, current in
      if previous, !current { Task { await viewModel.reloadAll() } }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await viewModel.reloadAll() } }
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
        filters
        content()
      }
      .padding(AEVYNOSpacing.md)
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
        Text(AppText.playbackUnavailable)
          .aevynoTypography(.status)
          .foregroundStyle(AEVYNOColor.secondaryText)
      }
      .padding(AEVYNOSpacing.md)
    }
    .background(AEVYNOColor.background)
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
  @State var viewModel: SourceManagementViewModel

  var body: some View {
    NavigationStack {
      List {
        if viewModel.isLoading {
          ProgressView(AppText.sourcesLoading)
        } else if viewModel.loadFailed {
          Button(AppText.retry) { Task { await viewModel.load() } }
        } else if viewModel.sources.isEmpty {
          ContentUnavailableView(
            AppText.sourcesEmptyTitle,
            systemImage: "externaldrive.badge.plus",
            description: Text(AppText.sourcesEmptyMessage)
          )
        } else {
          ForEach(viewModel.sources) { source in
            VStack(alignment: .leading) {
              Text(source.configuration.displayName)
              Text(AppText.sourceKind(source.configuration.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
              Button(AppText.refreshNow) {
                Task { await viewModel.refresh(id: source.id) }
              }
              .disabled(!source.configuration.isEnabled)
            }
          }
        }
      }
      .navigationTitle(AppText.sources)
      .toolbar { Button(AppText.done) { dismiss() } }
      .task { await viewModel.load() }
    }
  }
}
