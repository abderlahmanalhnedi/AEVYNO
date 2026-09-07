import Library
import SwiftUI

@main
struct AEVYNOiOSApp: App {
  var body: some Scene {
    WindowGroup {
      MobileHomeView(
        viewModel: HomeViewModel(
          loader: HomeLoader(
            fetchHomeSections: FetchHomeSections(
              repository: MockHomeRepository()
            )
          )
        )
      )
    }
  }
}
