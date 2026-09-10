import Library
import SwiftUI

@main
struct AEVYNOiOSApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: HomeViewModel
  private let refreshLifecycle: RefreshSchedulingLifecycleController

  init() {
    let serviceContainer = AppSourceServiceContainer()
    viewModel = HomeViewModel(
      loader: HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: MockHomeRepository())
      )
    )
    refreshLifecycle = RefreshSchedulingLifecycleController {
      try await serviceContainer.services().refreshScheduling
    }
  }

  var body: some Scene {
    WindowGroup {
      MobileHomeView(viewModel: viewModel)
        .onChange(of: scenePhase, initial: true) { _, phase in
          refreshLifecycle.transition(to: phase)
        }
    }
  }
}
