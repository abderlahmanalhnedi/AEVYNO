import Library
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let loader: HomeLoader
    private(set) var state: HomeLoadState = .loading

    init(loader: HomeLoader) {
        self.loader = loader
    }

    func loadIfNeeded() async {
        guard state == .loading else { return }
        state = await loader.load()
    }

    func reload() async {
        state = .loading
        state = await loader.load()
    }
}
