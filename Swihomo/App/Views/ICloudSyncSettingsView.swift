import SwiftUI

/// Dedicated iCloud sync management page, reachable from the Tools list. The
/// master switch gates everything; syncable categories are grouped by the
/// area they come from, each row's description stating exactly what it
/// covers. Chrome (title, back) is owned by the hosting container on every
/// platform: the macOS detail column and the iOS navigation stacks.
struct ICloudSyncSettingsView: View {
    @AppSetting(\.iCloudSyncEnabled) private var iCloudSyncEnabled
    @AppSetting(\.iCloudSyncGeneral) private var syncGeneral
    @AppSetting(\.iCloudSyncSorting) private var syncSorting
    @AppSetting(\.iCloudSyncNetwork) private var syncNetwork
    @AppSetting(\.iCloudSyncExperimental) private var syncExperimental
    @AppSetting(\.iCloudSyncProfiles) private var syncProfiles
    @AppSetting(\.iCloudSyncOverrides) private var syncOverrides
    @State private var showingDeleteConfirmation = false
    @ObservedObject private var syncController = SettingsSyncController.shared
    @ObservedObject private var statusStore = SyncStatusStore.shared

    var body: some View {
        formContent
            #if os(iOS)
            .uniformTopScrollEdge()
            #endif
            .detailPageTitle("tools.iCloudSync")
    }

    private var formContent: some View {
        Form {
            Section {
                PreferenceRow(
                    title: Text("tools.iCloudSync"),
                    description: Text("icloudSync.master.description")
                ) {
                    Toggle("tools.iCloudSync", isOn: $iCloudSyncEnabled)
                        .labelsHidden()
                }
            }

            Section {
                statusRow(title: "icloudSync.status.preferences", event: statusStore.preferencesEvent)
                statusRow(title: "icloudSync.status.profiles", event: statusStore.profilesEvent)

                Button("icloudSync.syncNow") {
                    syncController.syncNow()
                }
                .disabled(!iCloudSyncEnabled)
            } header: {
                SectionHeaderLabel("icloudSync.status", systemImage: "clock.arrow.circlepath")
            }

            if iCloudSyncEnabled {
                Section {
                    categoryRow(
                        titleKey: "icloudSync.category.general",
                        descriptionKey: "icloudSync.category.general.description",
                        isOn: $syncGeneral
                    )
                    categoryRow(
                        titleKey: "icloudSync.category.sorting",
                        descriptionKey: "icloudSync.category.sorting.description",
                        isOn: $syncSorting
                    )
                    categoryRow(
                        titleKey: "icloudSync.category.network",
                        descriptionKey: "icloudSync.category.network.description",
                        isOn: $syncNetwork
                    )
                    categoryRow(
                        titleKey: "icloudSync.category.experimental",
                        descriptionKey: "icloudSync.category.experimental.description",
                        isOn: $syncExperimental
                    )
                } header: {
                    SectionHeaderLabel("icloudSync.area.preferences", systemImage: "gearshape")
                }

                Section {
                    categoryRow(
                        titleKey: "icloudSync.category.profiles",
                        descriptionKey: "icloudSync.category.profiles.description",
                        isOn: $syncProfiles
                    )
                    categoryRow(
                        titleKey: "icloudSync.category.overrides",
                        descriptionKey: "icloudSync.category.overrides.description",
                        isOn: $syncOverrides
                    )
                } header: {
                    SectionHeaderLabel("icloudSync.area.profiles", systemImage: "doc.text")
                }

                Section {
                    PreferenceRow(
                        title: Text("icloudSync.deleteData"),
                        description: Text("icloudSync.deleteData.description")
                    ) {
                        Button("icloudSync.deleteData", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .labelsHidden()
                    }
                } header: {
                    SectionHeaderLabel("icloudSync.dangerZone", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            Text("icloudSync.deleteData.confirmationTitle"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("icloudSync.deleteData", role: .destructive) {
                SettingsSyncController.shared.deleteAllSyncedData()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("icloudSync.deleteData.confirmationMessage")
        }
        // Enable-time conflict: the cloud already holds synced settings and
        // the controller is holding all sync activity until this resolves.
        // Dismissing without a choice counts as cancel.
        .confirmationDialog(
            Text("icloudSync.enableConflict.title"),
            isPresented: Binding(
                get: { syncController.pendingEnableConflict },
                set: { if !$0 { syncController.resolveEnableConflict(.cancel) } }
            ),
            titleVisibility: .visible
        ) {
            Button("icloudSync.enableConflict.useRemote") {
                syncController.resolveEnableConflict(.useRemote)
            }
            Button("icloudSync.enableConflict.useLocal") {
                syncController.resolveEnableConflict(.useLocal)
            }
            Button("common.cancel", role: .cancel) {
                syncController.resolveEnableConflict(.cancel)
            }
        } message: {
            Text("icloudSync.enableConflict.message")
        }
    }

    /// One pipeline's latest event: source label, message (red on failure),
    /// and its timestamp.
    private func statusRow(title: LocalizedStringKey, event: SyncStatusStore.Event?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let event {
                Text(event.message)
                    .foregroundStyle(event.isError ? Color.red : Color.primary)
                Text(event.date.formatted(date: .numeric, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("icloudSync.status.none")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func categoryRow(
        titleKey: LocalizedStringKey,
        descriptionKey: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        PreferenceRow(
            title: Text(titleKey),
            description: Text(descriptionKey)
        ) {
            Toggle(titleKey, isOn: isOn)
                .labelsHidden()
        }
    }
}
