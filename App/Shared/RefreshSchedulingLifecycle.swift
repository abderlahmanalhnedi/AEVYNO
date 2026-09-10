import Library
import OSLog
import SwiftUI

actor AppSourceServiceContainer {
  private var resolvedServices: ProductionSourceServices?

  func services() async throws -> ProductionSourceServices {
    if let resolvedServices { return resolvedServices }
    let services = try await SourceManagementService.openDefaultServices()
    resolvedServices = services
    return services
  }
}

@MainActor
final class RefreshSchedulingLifecycleController {
  private let coordinator: LazyActiveRefreshSchedulingCoordinator
  private let logger = Logger(subsystem: "com.aevyno.app", category: "refresh-scheduling")
  private var transitionTask: Task<Void, Never>?

  init(schedulerFactory: @escaping LazyActiveRefreshSchedulingCoordinator.SchedulerFactory) {
    coordinator = LazyActiveRefreshSchedulingCoordinator(schedulerFactory: schedulerFactory)
  }

  func transition(to phase: ScenePhase) {
    transitionTask?.cancel()
    transitionTask = Task { [coordinator, logger] in
      if phase == .active {
        do {
          try await coordinator.activate()
        } catch is CancellationError {
          return
        } catch {
          logger.error("Automatic refresh scheduling could not start safely")
        }
      } else {
        await coordinator.deactivate()
      }
    }
  }
}
