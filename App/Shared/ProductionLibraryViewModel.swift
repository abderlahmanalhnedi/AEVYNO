import Foundation
import Library
import Observation

enum ProductionLibraryScreenState: Equatable {
  case loading
  case noSources
  case noCatalog
  case content
  case empty
  case searchPrompt
  case noResults
  case failure
}

@MainActor
@Observable
final class ProductionLibraryViewModel {
  typealias ServiceFactory = @Sendable () async throws -> any ProductionLibraryServing

  private let serviceFactory: ServiceFactory
  private var service: (any ProductionLibraryServing)?
  private var pager: LibraryPagingController?
  private var reloadTask: Task<Void, Never>?
  private var revisionTask: Task<Void, Never>?

  private(set) var context: ProductionLibraryContext?
  private(set) var items: [LibraryItemPresentation] = []
  private(set) var categories: [LibraryCategoryPresentation] = []
  private(set) var isLoadingPage = false
  private(set) var hasMore = false
  private(set) var screenState: ProductionLibraryScreenState = .loading

  var scope: LibraryBrowseScope = .library
  var selectedSourceID: LibrarySourcePresentation.ID?
  var selectedCategory: LibraryCategoryPresentation?
  var searchText = ""

  init(
    serviceFactory: @escaping ServiceFactory,
    initialQuery: LibraryQuery = LibraryQuery()
  ) {
    self.serviceFactory = serviceFactory
    scope = initialQuery.scope
    selectedSourceID = initialQuery.sourceID
    selectedCategory = initialQuery.category
    searchText = initialQuery.searchText
  }

  func loadIfNeeded(protecting itemID: String? = nil) async {
    guard service == nil else { return }
    await reloadAll(protecting: itemID)
  }

  func reloadAll(protecting itemID: String? = nil) async {
    screenState = context == nil ? .loading : screenState
    do {
      let resolved = try await resolvedService()
      let loadedContext = try await resolved.context()
      try Task.checkCancellation()
      context = loadedContext
      startRevisionObservation(using: resolved)

      guard !loadedContext.sources.isEmpty else {
        categories = []
        items = []
        screenState = .noSources
        return
      }
      guard loadedContext.committedCatalogCount > 0 else {
        categories = []
        items = []
        screenState = .noCatalog
        return
      }
      await loadCategories(using: resolved)
      await restartPage(using: resolved, protecting: itemID)
    } catch is CancellationError {
      return
    } catch {
      screenState = .failure
      isLoadingPage = false
    }
  }

  func selectScope(_ value: LibraryBrowseScope, protecting itemID: String? = nil) {
    scope = value
    selectedCategory = nil
    scheduleReload(debounced: false, protecting: itemID)
  }

  func selectSource(_ value: LibrarySourcePresentation.ID?, protecting itemID: String? = nil) {
    selectedSourceID = value
    selectedCategory = nil
    scheduleReload(debounced: false, protecting: itemID)
  }

  func selectCategory(_ value: LibraryCategoryPresentation?, protecting itemID: String? = nil) {
    selectedCategory = value
    scheduleReload(debounced: false, protecting: itemID)
  }

  func searchTextChanged() {
    guard scope == .search else { return }
    selectedCategory = nil
    scheduleReload(debounced: true, protecting: nil)
  }

  func submitSearch() {
    guard scope == .search else { return }
    scheduleReload(debounced: false, protecting: nil)
  }

  func retry(protecting itemID: String? = nil) {
    scheduleReload(debounced: false, protecting: itemID, includeContext: true)
  }

  func loadNext(protecting itemID: String?) async {
    guard let pager, !isLoadingPage, hasMore else { return }
    isLoadingPage = true
    let snapshot = await pager.loadNext(protecting: itemID)
    apply(snapshot)
  }

  var query: LibraryQuery {
    LibraryQuery(
      scope: scope,
      sourceID: selectedSourceID,
      category: selectedCategory,
      searchText: searchText
    )
  }

  private func resolvedService() async throws -> any ProductionLibraryServing {
    if let service { return service }
    let resolved = try await serviceFactory()
    service = resolved
    pager = LibraryPagingController(service: resolved)
    return resolved
  }

  private func scheduleReload(
    debounced: Bool,
    protecting itemID: String?,
    includeContext: Bool = false
  ) {
    reloadTask?.cancel()
    reloadTask = Task { [weak self] in
      if debounced {
        do {
          try await Task.sleep(for: .milliseconds(300))
        } catch {
          return
        }
      }
      guard let self else { return }
      if includeContext {
        await self.reloadAll(protecting: itemID)
      } else {
        await self.reloadQuery(protecting: itemID)
      }
    }
  }

  private func reloadQuery(protecting itemID: String?) async {
    do {
      let resolved = try await resolvedService()
      await loadCategories(using: resolved)
      await restartPage(using: resolved, protecting: itemID)
    } catch is CancellationError {
      return
    } catch {
      screenState = .failure
      isLoadingPage = false
    }
  }

  private func loadCategories(using service: any ProductionLibraryServing) async {
    do {
      categories = try await service.categories(
        matching: query,
        page: LibraryPageRequest(limit: LibraryPageRequest.maximumSize)
      )
    } catch is CancellationError {
      return
    } catch {
      categories = []
    }
  }

  private func restartPage(
    using service: any ProductionLibraryServing,
    protecting itemID: String?
  ) async {
    let activePager: LibraryPagingController
    if let pager {
      activePager = pager
    } else {
      let created = LibraryPagingController(service: service)
      pager = created
      activePager = created
    }
    isLoadingPage = true
    let snapshot = await activePager.restart(query: query, protecting: itemID)
    apply(snapshot)
  }

  private func apply(_ snapshot: LibraryPageSnapshot) {
    guard snapshot.query == query else { return }
    items = snapshot.items
    isLoadingPage = snapshot.isLoading
    hasMore = snapshot.hasMore
    if snapshot.error != nil {
      screenState = .failure
    } else if scope == .search,
      searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      screenState = .searchPrompt
    } else if items.isEmpty {
      screenState = scope == .search ? .noResults : .empty
    } else {
      screenState = .content
    }
  }

  private func startRevisionObservation(using service: any ProductionLibraryServing) {
    guard revisionTask == nil else { return }
    revisionTask = Task { [weak self] in
      let revisions = await service.revisions()
      for await _ in revisions {
        guard !Task.isCancelled, let self else { return }
        await self.reloadAll()
      }
    }
  }
}
