import Domain
import Library
import Observation

enum SourceOperationState: Equatable {
  case testing
  case connectionSucceeded
  case saving
  case saved
  case refreshing(CatalogRefreshStage)
  case enabled
  case disabled
  case deleted
  case failed(SourceManagementError)
  case cancelled
}

@MainActor
@Observable
final class SourceManagementViewModel {
  typealias ServiceFactory = @Sendable () async throws -> any SourceManaging

  private let serviceFactory: ServiceFactory
  private var service: (any SourceManaging)?
  private(set) var sources: [ManagedSource] = []
  private(set) var isLoading = true
  private(set) var loadFailed = false
  private(set) var operationState: SourceOperationState?

  init(serviceFactory: @escaping ServiceFactory) {
    self.serviceFactory = serviceFactory
  }

  func load() async {
    isLoading = true
    loadFailed = false
    do {
      let service = try await resolvedService()
      sources = try await service.listSources()
    } catch {
      loadFailed = true
    }
    isLoading = false
  }

  func validate(_ draft: SourceDraft, editing id: SourceConfiguration.ID?) async
    -> [SourceValidationIssue]
  {
    do {
      let service = try await resolvedService()
      return await service.validateDraft(draft, editing: id)
    } catch {
      return [SourceValidationIssue(field: .endpoint, reason: .invalidURL)]
    }
  }

  func testConnection(_ draft: SourceDraft, editing id: SourceConfiguration.ID?) async -> Bool {
    operationState = .testing
    do {
      _ = try await resolvedService().testConnection(draft, editing: id)
      operationState = .connectionSucceeded
      return true
    } catch is CancellationError {
      operationState = .cancelled
      return false
    } catch let error as SourceManagementError {
      operationState = .failed(error)
      return false
    } catch {
      operationState = .failed(.unreachableProvider)
      return false
    }
  }

  func save(_ draft: SourceDraft, editing id: SourceConfiguration.ID?) async -> Bool {
    operationState = .saving
    do {
      let service = try await resolvedService()
      if let id {
        _ = try await service.updateSource(id: id, from: draft)
      } else {
        _ = try await service.createSource(from: draft)
      }
      sources = try await service.listSources()
      operationState = .saved
      return true
    } catch let error as SourceManagementError {
      operationState = .failed(error)
      return false
    } catch {
      operationState = .failed(.persistenceFailure)
      return false
    }
  }

  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async {
    do {
      let service = try await resolvedService()
      try await service.setEnabled(isEnabled, id: id)
      sources = try await service.listSources()
      operationState = isEnabled ? .enabled : .disabled
    } catch let error as SourceManagementError {
      operationState = .failed(error)
    } catch {
      operationState = .failed(.persistenceFailure)
    }
  }

  func refresh(id: SourceConfiguration.ID) async {
    do {
      let service = try await resolvedService()
      _ = try await service.refreshNow(id: id) { stage in
        await MainActor.run { self.operationState = .refreshing(stage) }
      }
      sources = try await service.listSources()
    } catch is CancellationError {
      operationState = .cancelled
    } catch let error as SourceManagementError {
      operationState = .failed(error)
    } catch {
      operationState = .failed(.persistenceFailure)
    }
  }

  func delete(id: SourceConfiguration.ID) async -> Bool {
    do {
      let service = try await resolvedService()
      try await service.deleteSource(id: id)
      sources = try await service.listSources()
      operationState = .deleted
      return true
    } catch let error as SourceManagementError {
      operationState = .failed(error)
      return false
    } catch {
      operationState = .failed(.cleanupFailure)
      return false
    }
  }

  func clearOperationState() {
    operationState = nil
  }

  func reportValidationIssues(_ issues: [SourceValidationIssue]) {
    operationState = .failed(.invalidInput(issues))
  }

  private func resolvedService() async throws -> any SourceManaging {
    if let service { return service }
    let resolved = try await serviceFactory()
    service = resolved
    return resolved
  }
}
