import DesignSystem
import Library
import Playback
import SwiftUI

@main
struct AEVYNOiOSApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: HomeViewModel
  private let productionLibraryViewModel: ProductionLibraryViewModel
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory
  private let artworkPipeline: ArtworkImagePipeline
  private let usesSyntheticHome: Bool
  private let refreshLifecycle: RefreshSchedulingLifecycleController
  private let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  private let continueWatchingServiceFactory: ContinueWatchingViewModel.ServiceFactory
  private let favoritesServiceFactory: FavoritesViewModel.ServiceFactory

  init() {
    let serviceContainer = AppSourceServiceContainer()
    usesSyntheticHome = ProcessInfo.processInfo.arguments.contains("--ui-demo-home")
    viewModel = HomeViewModel(
      loader: HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: MockHomeRepository())
      )
    )
    refreshLifecycle = RefreshSchedulingLifecycleController {
      try await serviceContainer.services().refreshScheduling
    }
    productionLibraryViewModel = ProductionLibraryViewModel {
      try await serviceContainer.services().productionLibrary
    }
    sourceServiceFactory = { try await serviceContainer.services().sourceManagement }
    artworkPipeline = ArtworkImagePipeline()
    playbackServiceFactory = { try await serviceContainer.playbackDependencies() }
    continueWatchingServiceFactory = { try await serviceContainer.services().continueWatching }
    favoritesServiceFactory = { try await serviceContainer.services().favorites }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if usesSyntheticHome {
          MobileHomeView(viewModel: viewModel)
        } else {
          MobileProductionLibraryView(
            viewModel: productionLibraryViewModel,
            artworkPipeline: artworkPipeline,
            sourceServiceFactory: sourceServiceFactory,
            playbackServiceFactory: playbackServiceFactory,
            continueWatchingServiceFactory: continueWatchingServiceFactory,
            favoritesServiceFactory: favoritesServiceFactory
          )
        }
      }
      .onChange(of: scenePhase, initial: true) { _, phase in
        refreshLifecycle.transition(to: phase)
      }
    }
  }
}
