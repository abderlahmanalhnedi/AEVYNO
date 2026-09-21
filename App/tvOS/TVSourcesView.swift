import DesignSystem
import Domain
import Library
import SwiftUI

struct TVSourcesView: View {
  private enum FocusTarget: Hashable {
    case add
    case source(SourceConfiguration.ID)
  }

  @State private var viewModel: SourceManagementViewModel
  @State private var editorRoute: SourceEditorRoute?
  @FocusState private var focusedTarget: FocusTarget?
  @State private var rememberedSourceID: SourceConfiguration.ID?
  @Namespace private var focusNamespace
  @Environment(\.resetFocus) private var resetFocus

  private let newSourceDraft: SourceDraft?

  init(
    serviceFactory: @escaping SourceManagementViewModel.ServiceFactory,
    newSourceDraft: SourceDraft? = nil
  ) {
    _viewModel = State(initialValue: SourceManagementViewModel(serviceFactory: serviceFactory))
    self.newSourceDraft = newSourceDraft
  }

  var body: some View {
    ZStack {
      AEVYNOColor.background.ignoresSafeArea()
      content
    }
    .navigationTitle(AppText.sources)
    .navigationDestination(item: $editorRoute) { route in
      TVSourceEditorView(
        source: route.source,
        initialDraft: route.source == nil ? newSourceDraft : nil,
        viewModel: viewModel,
        onSaved: { sourceID in
          rememberedSourceID = sourceID
          editorRoute = nil
        },
        onDeleted: {
          rememberedSourceID = nil
          editorRoute = nil
        }
      )
    }
    .task { await viewModel.load() }
    .onChange(of: focusedTarget) { _, target in
      if case .source(let id) = target { rememberedSourceID = id }
    }
    .onChange(of: editorRoute?.id) { previous, current in
      guard previous != nil, current == nil else { return }
      restoreListFocus()
    }
    .accessibilityIdentifier("sources.screen")
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      ProgressView(AppText.sourcesLoading)
        .accessibilityIdentifier("sources.loading")
    } else if viewModel.loadFailed {
      StatusPanel(
        symbolName: "externaldrive.badge.exclamationmark",
        title: AppText.sourcesUnavailable,
        message: AppText.sourcesUnavailableMessage,
        actionTitle: AppText.retry,
        actionAccessibilityHint: AppText.retryAccessibilityHint
      ) {
        Task { await viewModel.load() }
      }
      .accessibilityIdentifier("sources.error")
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
          header
          if viewModel.sources.isEmpty {
            emptyState
          } else {
            ForEach(viewModel.sources) { source in
              sourceRow(source)
            }
          }
        }
        .padding(.horizontal, AEVYNOSpacing.xxl)
        .padding(.vertical, AEVYNOSpacing.xl)
      }
      .scrollIndicators(.hidden)
      .focusScope(focusNamespace)
      .defaultFocus($focusedTarget, preferredListFocus, priority: .userInitiated)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: AEVYNOSpacing.xl) {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
        Text(AppText.sources)
          .aevynoTypography(.detailTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
        Text(AppText.sourcesSubtitle)
          .aevynoTypography(.status)
          .foregroundStyle(AEVYNOColor.secondaryText)
      }
      Spacer()
      Button {
        editorRoute = SourceEditorRoute(source: nil)
      } label: {
        Label(AppText.addSource, systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .tint(AEVYNOColor.accent)
      .focused($focusedTarget, equals: .add)
      .accessibilityIdentifier("sources.add")
      .accessibilityHint(AppText.addSourceAccessibilityHint)
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Image(systemName: "rectangle.stack.badge.plus")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(AEVYNOColor.accent)
        .accessibilityHidden(true)
      Text(AppText.sourcesEmptyTitle)
        .aevynoTypography(.sectionTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
      Text(AppText.sourcesEmptyMessage)
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.secondaryText)
    }
    .padding(AEVYNOSpacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AEVYNOColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sources.empty")
  }

  private func sourceRow(_ source: ManagedSource) -> some View {
    let configuration = source.configuration
    return Button {
      rememberedSourceID = configuration.id
      editorRoute = SourceEditorRoute(source: source)
    } label: {
      HStack(spacing: AEVYNOSpacing.lg) {
        Image(systemName: configuration.kind == .m3u ? "list.bullet.rectangle" : "server.rack")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(AEVYNOColor.accent)
          .frame(width: 64)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
          Text(configuration.displayName)
            .aevynoTypography(.sectionTitle)
            .foregroundStyle(AEVYNOColor.primaryText)
          Text(AppText.sourceKind(configuration.kind))
            .aevynoTypography(.metadata)
            .foregroundStyle(AEVYNOColor.secondaryText)
        }
        Spacer()
        Text(configuration.isEnabled ? AppText.enabled : AppText.disabled)
          .aevynoTypography(.metadata)
          .foregroundStyle(configuration.isEnabled ? AEVYNOColor.accent : AEVYNOColor.secondaryText)
      }
      .padding(AEVYNOSpacing.lg)
      .background(AEVYNOColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
    }
    .buttonStyle(.plain)
    .focused($focusedTarget, equals: .source(configuration.id))
    .accessibilityIdentifier("sources.row")
    .accessibilityLabel(
      AppText.sourceRowAccessibilityLabel(
        name: configuration.displayName,
        kind: AppText.sourceKind(configuration.kind),
        status: configuration.isEnabled ? AppText.enabled : AppText.disabled
      )
    )
    .accessibilityHint(AppText.editSourceAccessibilityHint)
  }

  private var preferredListFocus: FocusTarget {
    if let rememberedSourceID,
      viewModel.sources.contains(where: { $0.id == rememberedSourceID })
    {
      return .source(rememberedSourceID)
    }
    return viewModel.sources.first.map { .source($0.id) } ?? .add
  }

  private func restoreListFocus() {
    let target = preferredListFocus
    focusedTarget = nil
    Task { @MainActor in
      await Task.yield()
      focusedTarget = target
      await Task.yield()
      resetFocus(in: focusNamespace)
    }
  }
}

private struct SourceEditorRoute: Identifiable, Hashable {
  let id = UUID()
  let source: ManagedSource?

  static func == (lhs: SourceEditorRoute, rhs: SourceEditorRoute) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

private struct TVSourceEditorView: View {
  private enum Field: Hashable {
    case name
    case kind
    case endpoint
    case epgEndpoint
    case username
    case password
    case replaceCredential
    case refreshPolicy
    case test
    case save
    case enable
    case refresh
    case delete
  }

  let source: ManagedSource?
  let initialDraft: SourceDraft?
  let viewModel: SourceManagementViewModel
  let onSaved: (SourceConfiguration.ID) -> Void
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
  @FocusState private var focusedField: Field?
  @Namespace private var focusNamespace

  init(
    source: ManagedSource?,
    initialDraft: SourceDraft?,
    viewModel: SourceManagementViewModel,
    onSaved: @escaping (SourceConfiguration.ID) -> Void,
    onDeleted: @escaping () -> Void
  ) {
    self.source = source
    self.initialDraft = initialDraft
    self.viewModel = viewModel
    self.onSaved = onSaved
    self.onDeleted = onDeleted
    _displayName = State(
      initialValue: source?.configuration.displayName ?? initialDraft?.displayName ?? "")
    _kind = State(
      initialValue: source?.configuration.kind ?? initialDraft?.kind ?? .xtreamCompatible)
    _endpoint = State(
      initialValue: source?.configuration.endpoint?.url.absoluteString ?? initialDraft?.endpoint
        ?? "")
    _epgEndpoint = State(
      initialValue: source?.configuration.epgConfiguration?.endpoint.url.absoluteString
        ?? initialDraft?.epgEndpoint ?? "")
    _isEnabled = State(
      initialValue: source?.configuration.isEnabled ?? initialDraft?.isEnabled ?? true)
    _refreshPolicy = State(
      initialValue: source?.configuration.refreshPolicy ?? initialDraft?.refreshPolicy
        ?? .manualOnly)
    _replacingCredential = State(initialValue: source == nil)
    if case .replace(let username, let secret) = initialDraft?.credential {
      _username = State(initialValue: username)
      _password = State(initialValue: secret)
    }
  }

  var body: some View {
    ZStack {
      AEVYNOColor.background.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
          Text(source == nil ? AppText.addSource : AppText.editSource)
            .aevynoTypography(.detailTitle)
            .foregroundStyle(AEVYNOColor.primaryText)
          form
          refreshPolicyPanel
          schedulingStatus
          operationStatus
          actions
        }
        .padding(.horizontal, AEVYNOSpacing.xxl)
        .padding(.vertical, AEVYNOSpacing.xl)
      }
      .scrollIndicators(.hidden)
    }
    .navigationTitle(source == nil ? AppText.addSource : AppText.editSource)
    .focusScope(focusNamespace)
    .defaultFocus($focusedField, .name, priority: .userInitiated)
    .task { viewModel.clearOperationState() }
    .confirmationDialog(
      AppText.deleteSourceConfirmationTitle,
      isPresented: $showsDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(AppText.delete, role: .destructive) {
        guard let id = source?.id else { return }
        Task {
          if await viewModel.delete(id: id) { onDeleted() }
        }
      }
      Button(AppText.cancel, role: .cancel) {}
    } message: {
      Text(AppText.deleteSourceConfirmationMessage)
    }
    .accessibilityIdentifier("source.editor")
  }

  private var refreshPolicyPanel: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      Text(AppText.automaticRefresh)
        .aevynoTypography(.sectionTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
        .accessibilityIdentifier("source.refresh-policy-title")
      Picker(AppText.automaticRefresh, selection: $refreshPolicy) {
        Text(AppText.manualOnly).tag(RefreshPolicy.manualOnly)
        Text(AppText.every6Hours).tag(RefreshPolicy.automatic(.every6Hours))
        Text(AppText.every12Hours).tag(RefreshPolicy.automatic(.every12Hours))
        Text(AppText.daily).tag(RefreshPolicy.automatic(.daily))
      }
      .pickerStyle(.segmented)
      .focused($focusedField, equals: .refreshPolicy)
      .accessibilityIdentifier("source.refresh-policy")
      .accessibilityHint(AppText.automaticRefreshAccessibilityHint)

      Text(AppText.automaticRefreshActiveExplanation)
        .aevynoTypography(.metadata)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .accessibilityIdentifier("source.refresh-policy-explanation")
    }
    .padding(AEVYNOSpacing.lg)
    .background(AEVYNOColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
  }

  @ViewBuilder
  private var schedulingStatus: some View {
    if let source {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
        Label(
          AppText.refreshPolicy(refreshPolicy),
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.primaryText)
        .accessibilityIdentifier("source.current-policy")

        if !isEnabled, case .automatic = refreshPolicy {
          Text(AppText.automaticRefreshPaused)
            .accessibilityIdentifier("source.schedule-paused")
        }

        Text(AppText.lastRefreshed(source.refreshMetadata?.lastSuccessfulAt))
          .accessibilityIdentifier("source.last-refreshed")

        if let metadata = source.refreshMetadata {
          Text(AppText.lastAttempt(metadata.lastAttemptedAt, result: metadata.lastResult))
            .accessibilityIdentifier("source.last-attempt")
        }

        switch schedulingEvaluation(for: source) {
        case .due:
          Text(AppText.automaticRefreshEligibleNow)
            .accessibilityIdentifier("source.next-eligible")
        case .skipped(_, let nextEligibleAt):
          if let nextEligibleAt {
            Text(AppText.eligibleAfter(nextEligibleAt))
              .accessibilityIdentifier("source.next-eligible")
          }
        }
      }
      .aevynoTypography(.metadata)
      .foregroundStyle(AEVYNOColor.secondaryText)
      .padding(AEVYNOSpacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(AEVYNOColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("source.schedule-status")
    }
  }

  private func schedulingEvaluation(for source: ManagedSource) -> AutomaticRefreshEvaluation {
    let configuration = source.configuration
    let displayedConfiguration = SourceConfiguration(
      id: configuration.id,
      displayName: configuration.displayName,
      kind: configuration.kind,
      endpoint: configuration.endpoint,
      credentialReference: configuration.credentialReference,
      isEnabled: isEnabled,
      refreshPolicy: refreshPolicy,
      epgConfiguration: configuration.epgConfiguration
    )
    return RefreshPolicyEvaluator().evaluate(
      source: displayedConfiguration,
      metadata: source.refreshMetadata,
      now: Date()
    )
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      TextField(AppText.sourceName, text: $displayName)
        .textContentType(.name)
        .focused($focusedField, equals: .name)
        .accessibilityIdentifier("source.name")

      Picker(AppText.sourceType, selection: $kind) {
        Text(AppText.xtreamCompatible).tag(SourceKind.xtreamCompatible)
        Text(AppText.m3uPlaylist).tag(SourceKind.m3u)
      }
      .pickerStyle(.segmented)
      .disabled(source != nil)
      .focused($focusedField, equals: .kind)
      .accessibilityIdentifier("source.kind")

      TextField(AppText.serverAddress, text: $endpoint)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .focused($focusedField, equals: .endpoint)
        .accessibilityIdentifier("source.endpoint")

      if kind == .xtreamCompatible {
        credentialFields
      } else {
        TextField(AppText.xmltvEndpoint, text: $epgEndpoint)
          .textContentType(.URL)
          .textInputAutocapitalization(.never)
          .focused($focusedField, equals: .epgEndpoint)
          .accessibilityIdentifier("source.epg-endpoint")
          .accessibilityHint(AppText.xmltvEndpointAccessibilityHint)
        Text(AppText.m3uQueryLimitation)
          .aevynoTypography(.metadata)
          .foregroundStyle(AEVYNOColor.secondaryText)
          .accessibilityIdentifier("source.m3u-limitation")
      }
    }
    .padding(AEVYNOSpacing.lg)
    .background(AEVYNOColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
  }

  @ViewBuilder
  private var credentialFields: some View {
    if source != nil, !replacingCredential {
      HStack(spacing: AEVYNOSpacing.md) {
        Label(AppText.credentialSaved, systemImage: "checkmark.shield")
          .foregroundStyle(AEVYNOColor.accent)
        Spacer()
        Button(AppText.replaceCredential) { replacingCredential = true }
          .focused($focusedField, equals: .replaceCredential)
          .accessibilityIdentifier("source.replace-credential")
          .accessibilityHint(AppText.replaceCredentialAccessibilityHint)
      }
    } else {
      TextField(AppText.username, text: $username)
        .textContentType(.username)
        .textInputAutocapitalization(.never)
        .focused($focusedField, equals: .username)
        .accessibilityIdentifier("source.username")
      SecureField(AppText.password, text: $password)
        .textContentType(.password)
        .focused($focusedField, equals: .password)
        .accessibilityIdentifier("source.password")
        .accessibilityLabel(AppText.password)
        .accessibilityHint(AppText.passwordAccessibilityHint)
    }
  }

  @ViewBuilder
  private var operationStatus: some View {
    if let state = viewModel.operationState {
      Label(AppText.sourceOperationState(state), systemImage: statusSymbol(state))
        .aevynoTypography(.status)
        .foregroundStyle(statusColor(state))
        .accessibilityIdentifier("source.status")
        .accessibilityLabel(AppText.sourceOperationState(state))
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      HStack(spacing: AEVYNOSpacing.md) {
        Button(AppText.testConnection) { testConnection() }
          .focused($focusedField, equals: .test)
          .accessibilityIdentifier("source.test")
          .accessibilityHint(AppText.testConnectionAccessibilityHint)
        Button(AppText.save) { save() }
          .buttonStyle(.borderedProminent)
          .tint(AEVYNOColor.accent)
          .focused($focusedField, equals: .save)
          .accessibilityIdentifier("source.save")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .focusSection()

      if let source {
        HStack(spacing: AEVYNOSpacing.md) {
          Button(isEnabled ? AppText.disable : AppText.enable) {
            Task {
              await viewModel.setEnabled(!isEnabled, id: source.id)
              if !(viewModel.operationState?.isFailure ?? false) { isEnabled.toggle() }
            }
          }
          .focused($focusedField, equals: .enable)
          .accessibilityIdentifier("source.enable")

          Button(AppText.refreshNow) {
            Task { await viewModel.refresh(id: source.id) }
          }
          .disabled(!isEnabled)
          .focused($focusedField, equals: .refresh)
          .accessibilityIdentifier("source.refresh")

          Button(AppText.delete, role: .destructive) { showsDeleteConfirmation = true }
            .focused($focusedField, equals: .delete)
            .accessibilityIdentifier("source.delete")
            .accessibilityHint(AppText.deleteAccessibilityHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
      }
    }
  }

  private func draft() -> SourceDraft {
    let credential: SourceDraft.CredentialInput
    if kind == .m3u {
      credential = .none
    } else if source != nil, !replacingCredential {
      credential = .unchanged
    } else {
      credential = .replace(username: username, secret: password)
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
        focus(first: issues)
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
        focus(first: issues)
        return
      }
      let succeeded = await viewModel.save(input, editing: source?.id)
      if succeeded, let savedID = viewModel.lastSavedSourceID {
        password = ""
        username = ""
        onSaved(savedID)
      }
    }
  }

  private func focus(first issues: [SourceValidationIssue]) {
    guard let issue = issues.first else { return }
    switch issue.field {
    case .displayName: focusedField = .name
    case .sourceKind: focusedField = .kind
    case .endpoint: focusedField = .endpoint
    case .epgEndpoint: focusedField = .epgEndpoint
    case .username: focusedField = .username
    case .credential: focusedField = .password
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
