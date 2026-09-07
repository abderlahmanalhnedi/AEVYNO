import Library
import SwiftUI

@main
struct AEVYNOTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVHomeView(
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
