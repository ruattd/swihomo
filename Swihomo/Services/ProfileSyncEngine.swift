import CloudKit
import Foundation
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    /// Posted (from any context) after the profile sync engine applied remote
    /// changes to the local profile store.
    static let profileSyncDidApplyRemoteChanges = Notification.Name("SwihomoProfileSyncDidApplyRemoteChanges")
}

/// Syncs profiles and runtime overrides through the owner's private CloudKit
/// database. Lives entirely in the app process; the packet tunnel extension
/// never touches iCloud.
///
/// Design notes:
/// - Merge is a tokenless three-way diff (local / remote / persisted base)
///   over a full zone fetch. The base records only state CloudKit has
///   confirmed — a profile enters it solely after a successful upload — so a
///   profile that never reached iCloud can never be mistaken for remotely
///   deleted. The base is persisted to disk (sync-base.json) so deletion
///   semantics survive relaunches.
/// - The base is bound to a zone generation (a random UUID in a singleton
///   `ZoneInfo` record). A missing or different generation while a base
///   exists means another device deleted the iCloud data: fall silent,
///   discard the base, and never delete local data.
/// - Last-writer-wins per profile by `Profile.updatedAt`, re-validated inside
///   the repository actor at apply time. Overrides use
///   `ClientSnapshot.overridesUpdatedAt`. All compared timestamps are
///   quantized to whole seconds at the mutation sites so CloudKit's
///   millisecond precision and the manifest's second-precision ISO8601
///   encoding cannot cause perpetual re-upload churn.
/// - `activeProfileID` is intentionally NOT synced: which profile is in use is
///   a per-device choice. `ProxyOverrides.controllerSecret` is a per-device
///   credential: stripped on push, local value preserved on apply.
/// - There is no APNs subscription; sync runs on toggle-on, on local saves, on
///   a 120s timer, and when the app becomes active.
actor ProfileSyncEngine {
    static let shared = ProfileSyncEngine()

    private enum RecordType {
        static let profile = "Profile"
        static let overrides = "Overrides"
        static let zoneInfo = "ZoneInfo"
    }

    private enum Field {
        static let name = "name"
        static let source = "source"
        static let remoteURL = "remoteURL"
        static let customUserAgent = "customUserAgent"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let lastFetchedAt = "lastFetchedAt"
        static let subscriptionInfo = "subscriptionInfo"
        static let customOverridesEnabled = "customOverridesEnabled"
        static let customOverrideYAML = "customOverrideYAML"
        static let contents = "contents"
        static let payload = "payload"
        static let generation = "generation"
    }

    /// What CloudKit is known to hold, tagged with the zone generation it
    /// belongs to. Profile keys are UUID strings for JSON-friendly encoding.
    private struct SyncBase: Codable {
        var zoneGeneration: String
        var profiles: [String: Profile]
        var overridesUpdatedAt: Date?
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.swihomo.client",
        category: "ProfileSync"
    )
    private let container = CKContainer(identifier: "iCloud.com.swihomo.client")
    private let zoneID = CKRecordZone.ID(zoneName: "SwihomoProfiles", ownerName: CKCurrentUserDefaultName)
    private let overridesRecordID: CKRecord.ID
    private let zoneInfoRecordID: CKRecord.ID

    private var repository: SharedProfileRepository?
    private var base: SyncBase?
    private var didPrepare = false
    private var isSyncing = false
    private var cycleInFlight = false
    private var cycleRequestedWhileBusy = false
    /// Bumped whenever sync stops or cloud data is deleted; a cycle that
    /// started before the bump discards its results instead of rebasing.
    private var epoch = 0
    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var lastObservedState: (profiles: [Profile], overrides: ProxyOverrides, overridesUpdatedAt: Date)?

    private var database: CKDatabase { container.privateCloudDatabase }

    private static let pendingDeletionDefaultsKey = "profileSync.pendingZoneDeletion"
    private static let pendingDeletionGenerationDefaultsKey = "profileSync.pendingZoneDeletionGeneration"

    private init() {
        overridesRecordID = CKRecord.ID(recordName: "overrides", zoneID: zoneID)
        zoneInfoRecordID = CKRecord.ID(recordName: "zone-info", zoneID: zoneID)
    }

    // MARK: - Lifecycle

    func start(repository: SharedProfileRepository) async {
        guard self.repository == nil else { return }
        self.repository = repository
        loadBase()
        await repository.setSnapshotSaveObserver { snapshot in
            Task { await ProfileSyncEngine.shared.localSnapshotDidChange(snapshot) }
        }
        await configurationDidChange()
    }

    /// Re-evaluates the sync settings and starts/stops activity accordingly.
    /// Cheap to call repeatedly; no-ops when nothing changed.
    func configurationDidChange() async {
        guard repository != nil else { return }
        let settings = await MainActor.run { SettingsStore.shared.settings }
        guard !ScreenshotDemoMode.isEnabled else { return }

        if settings.iCloudSyncEnabled, !didPrepare {
            // "Prepare" is the only thing that runs while every content switch
            // is off: account check plus zone creation, no record traffic.
            await prepare()
        }

        // A read-only store (another instance holds the storage lock) can
        // load but not apply changes; syncing against it would poison the
        // merge base, so the engine stays idle.
        let repositoryIsReadOnly = await repository?.isStorageReadOnly ?? true
        let shouldSync = settings.iCloudSyncEnabled && settings.iCloudSyncProfiles && !repositoryIsReadOnly
        if shouldSync, !isSyncing, didPrepare {
            isSyncing = true
            startPolling()
            await syncCycle()
        } else if !shouldSync, isSyncing {
            epoch &+= 1
            stopSync()
        }
    }

    /// Deletes the whole sync zone and resets local sync state. Local profile
    /// data is untouched. Runs regardless of toggle state: the user asked to
    /// remove cloud data, whatever is currently syncing. A failed deletion
    /// (e.g. offline) is retried by `prepare()`.
    func deleteAllSyncedData() async {
        epoch &+= 1
        stopSync()
        didPrepare = false
        // Remember which zone generation the delete targets: if it fails and
        // a peer recreates and repopulates the zone in the meantime, the
        // retry in prepare() must not destroy that new data.
        let targetGeneration = base?.zoneGeneration
        clearBase()
        do {
            try await database.deleteRecordZone(withID: zoneID)
            setPendingZoneDeletion(false, generation: nil)
            logger.notice("Deleted the iCloud profile sync zone.")
        } catch let error as CKError where error.code == .zoneNotFound {
            setPendingZoneDeletion(false, generation: nil)
            logger.notice("The iCloud profile sync zone was already gone.")
        } catch {
            setPendingZoneDeletion(true, generation: targetGeneration)
            logger.error("Unable to delete the iCloud profile sync zone (will retry): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called when KVS reports the sync configuration was deleted remotely:
    /// the cloud data is gone, so drop the base (it belongs to the deleted
    /// zone generation) and stop. Local profile data is untouched.
    func remoteDataWasDeleted() async {
        epoch &+= 1
        stopSync()
        clearBase()
    }

    // MARK: - Preparation

    private func prepare() async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.error("iCloud account is unavailable (status \(status.rawValue, privacy: .public)); profile sync stays idle.")
                return
            }

            if isPendingZoneDeletion() {
                // Retry only against the generation the delete targeted. A
                // zone-info record with a different generation means a peer
                // recreated the zone and is syncing again — that data must
                // survive. Transient read failures keep the flag so the
                // retry happens on a later prepare().
                var shouldDelete = true
                if let targetGeneration = pendingDeletionGeneration() {
                    let zoneInfo: CKRecord?
                    do {
                        zoneInfo = try await database.record(for: zoneInfoRecordID)
                    } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                        // No zone-info record: nothing new to protect.
                        zoneInfo = nil
                    }
                    // Any other error propagates to the outer catch; the
                    // pending flag stays set for the next prepare().
                    if let zoneInfo {
                        guard let generation = zoneInfo[Field.generation] as? String else {
                            logger.error("Zone info unreadable during pending delete; the retry stays pending.")
                            return
                        }
                        shouldDelete = generation == targetGeneration
                    }
                }
                if shouldDelete {
                    do {
                        try await database.deleteRecordZone(withID: zoneID)
                    } catch let error as CKError where error.code == .zoneNotFound {
                        // Already gone — the deletion has effectively completed.
                    }
                    didPrepare = true
                    // Skip recreating the zone this once so the deletion
                    // sticks; it is recreated when profile sync starts.
                    logger.notice("Completed the pending iCloud zone deletion.")
                } else {
                    logger.notice("Dropped the pending zone deletion: the zone was recreated by another device.")
                }
                setPendingZoneDeletion(false, generation: nil)
                if shouldDelete { return }
            }

            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            didPrepare = true
            logger.notice("iCloud profile sync zone is ready.")
        } catch {
            logger.error("Unable to prepare iCloud profile sync: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                await self?.syncCycle()
            }
        }
        #if os(macOS)
        let notificationName = NSApplication.didBecomeActiveNotification
        #else
        let notificationName = UIApplication.didBecomeActiveNotification
        #endif
        activationObserver = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { _ in
            Task { await ProfileSyncEngine.shared.syncCycle() }
        }
    }

    private func stopSync() {
        isSyncing = false
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        lastObservedState = nil
    }

    // MARK: - Outbound trigger

    /// Fired by the repository after every local manifest save. Sync-originated
    /// saves never reach here (the repository suppresses them).
    private func localSnapshotDidChange(_ snapshot: ClientSnapshot) async {
        guard isSyncing else { return }
        let state = (snapshot.profiles, snapshot.overrides, snapshot.overridesUpdatedAt)
        if let last = lastObservedState, last == state { return }
        lastObservedState = state
        await syncCycle()
    }

    // MARK: - Sync cycle

    /// Serializes full bidirectional merge cycles. Saves arriving mid-cycle
    /// request exactly one follow-up run so nothing is lost.
    private func syncCycle() async {
        guard isSyncing, didPrepare, repository != nil else { return }
        if cycleInFlight {
            cycleRequestedWhileBusy = true
            return
        }
        cycleInFlight = true
        defer { cycleInFlight = false }
        repeat {
            cycleRequestedWhileBusy = false
            await runCycle()
        } while cycleRequestedWhileBusy && isSyncing
    }

    private func runCycle() async {
        guard let repository, isSyncing else { return }
        // Syncing against a read-only store (another instance holds the
        // storage lock) would poison the merge base, so stay idle.
        if await repository.isStorageReadOnly { return }
        let cycleEpoch = epoch

        let remote: RemoteState
        do {
            remote = try await fetchRemoteState()
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            if base != nil {
                // The zone existed before (we hold a base) and is now gone:
                // deleted elsewhere. Fall silent.
                await handleRemoteWipe()
            } else {
                // Never synced (or the pending-deletion retry just cleared the
                // zone): recreate it and let the repeat loop claim a fresh
                // generation.
                do {
                    guard epoch == cycleEpoch else { return }
                    _ = try await database.save(CKRecordZone(zoneID: zoneID))
                    cycleRequestedWhileBusy = true
                } catch {
                    logger.error("Unable to recreate the iCloud profile sync zone: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        } catch let error as CKError where error.code == .notAuthenticated {
            logger.error("iCloud account signed out; profile sync paused.")
            epoch &+= 1
            stopSync()
            return
        } catch {
            logger.error("Unable to fetch iCloud profile changes: \(error.localizedDescription, privacy: .public)")
            return
        }

        // A zone-info record that exists but cannot be read must not be
        // mistaken for a remote wipe; skip this cycle instead.
        if remote.zoneInfoUnreadable {
            logger.error("The iCloud sync zone info is unreadable; skipping this cycle.")
            return
        }

        // Zone generation check. A base tagged with another (or a missing)
        // generation means another device deleted the iCloud data: fall silent
        // instead of deleting local profiles or re-uploading over the wipe.
        let generation: String
        if let fetchedGeneration = remote.zoneGeneration {
            if let base, base.zoneGeneration != fetchedGeneration {
                // A different generation with the zone intact means a peer
                // deleted the iCloud data and sync was re-enabled afterwards.
                // Adopt the new generation: a nil-base merge never deletes
                // local data, and it lets this device rejoin the new zone.
                clearBase()
            }
            generation = fetchedGeneration
        } else {
            if base != nil {
                await handleRemoteWipe()
                return
            }
            // Fresh zone and nothing synced yet: claim the generation. If a
            // peer raced us, the conditional save fails and the next cycle
            // adopts the winner's generation.
            do {
                guard epoch == cycleEpoch else { return }
                generation = try await claimZoneGeneration()
            } catch {
                logger.notice("Another device claimed the sync zone generation first; adopting it on the next cycle.")
                return
            }
        }

        let local: ClientSnapshot
        do {
            local = try await repository.loadSnapshot()
        } catch {
            logger.error("Unable to read the local profile store for sync: \(error.localizedDescription, privacy: .public)")
            return
        }
        lastObservedState = (local.profiles, local.overrides, local.overridesUpdatedAt)

        let baseProfiles: [String: Profile] = base?.profiles ?? [:]
        let localProfiles = Dictionary(uniqueKeysWithValues: local.profiles.map { ($0.id, $0) })

        var localUpserts: [(profile: Profile, contents: String)] = []
        var localDeletions: [(id: UUID, baseUpdatedAt: Date?)] = []
        var remoteUpserts: [CKRecord] = []
        var remoteDeletions: [CKRecord.ID] = []
        var assetFiles: [URL] = []
        defer {
            for file in assetFiles {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Records that are present but unreadable are unknown, not deleted:
        // exclude them from the merge and carry their base entries forward.
        let unreadableIDs = Set(remote.undecodableRecordNames.compactMap { UUID(uuidString: $0) })
        let allIDs = Set(localProfiles.keys).union(remote.profiles.keys).subtracting(unreadableIDs)
        for id in allIDs {
            let localProfile = localProfiles[id]
            let remoteEntry = remote.profiles[id]
            let baseProfile = baseProfiles[id.uuidString]

            switch (localProfile, remoteEntry) {
            case (.none, .some(let remoteEntry)):
                if let baseProfile {
                    // Known to both sides before and now gone locally: this
                    // device deleted it. Propagate the deletion unless the
                    // remote side edited the profile afterwards.
                    if remoteEntry.profile.updatedAt > baseProfile.updatedAt {
                        localUpserts.append((remoteEntry.profile, remoteEntry.contents))
                    } else {
                        remoteDeletions.append(CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
                    }
                } else {
                    // New profile from another device.
                    localUpserts.append((remoteEntry.profile, remoteEntry.contents))
                }
            case (.some(let localProfile), .none):
                if let baseProfile {
                    // Was synced, vanished remotely: deleted elsewhere. A local
                    // edit made after the base version wins instead.
                    if localProfile.updatedAt > baseProfile.updatedAt {
                        if let (record, assetFile) = await stagedProfile(localProfile, repository: repository) {
                            if let assetFile { assetFiles.append(assetFile) }
                            remoteUpserts.append(record)
                        }
                    } else {
                        localDeletions.append((id, baseProfile.updatedAt))
                    }
                } else {
                    // Never synced: upload it.
                    if let (record, assetFile) = await stagedProfile(localProfile, repository: repository) {
                        if let assetFile { assetFiles.append(assetFile) }
                        remoteUpserts.append(record)
                    }
                }
            case (.some(let localProfile), .some(let remoteEntry)):
                if remoteEntry.profile.updatedAt > localProfile.updatedAt {
                    localUpserts.append((remoteEntry.profile, remoteEntry.contents))
                } else if localProfile.updatedAt > remoteEntry.profile.updatedAt {
                    if let (record, assetFile) = await stagedProfile(localProfile, repository: repository) {
                        if let assetFile { assetFiles.append(assetFile) }
                        remoteUpserts.append(record)
                    }
                } else {
                    // Equal timestamps (possible with second-precision
                    // quantization): take the remote version so same-second
                    // edits on two devices converge on the server's copy.
                    let localContents = try? await repository.profileContents(for: id)
                    if localProfile != remoteEntry.profile || localContents != remoteEntry.contents {
                        localUpserts.append((remoteEntry.profile, remoteEntry.contents))
                    }
                }
            case (.none, .none):
                continue
            }
        }

        // Overrides: last-writer-wins on overridesUpdatedAt, secret
        // preserved. An unreadable remote record is unknown state, not
        // absence: skip both directions for this cycle.
        var overridesApply: (value: ProxyOverrides, updatedAt: Date)?
        var overridesRecord: CKRecord?
        if !remote.overridesUnreadable {
            if let remoteOverrides = remote.overrides, remoteOverrides.updatedAt > local.overridesUpdatedAt {
                var value = remoteOverrides.value
                value.controllerSecret = local.overrides.controllerSecret
                overridesApply = (value, remoteOverrides.updatedAt)
            }
            let shouldPushOverrides = local.overridesUpdatedAt != .distantPast
                && local.overridesUpdatedAt > remote.overrides?.updatedAt ?? .distantPast
            if shouldPushOverrides {
                overridesRecord = try? makeOverridesRecord(local.overrides, updatedAt: local.overridesUpdatedAt)
                if let overridesRecord {
                    remoteUpserts.append(overridesRecord)
                }
            }
        }

        var applyResult: SharedProfileRepository.SyncApplyResult?
        if !localUpserts.isEmpty || !localDeletions.isEmpty || overridesApply != nil {
            do {
                applyResult = try await repository.applySyncedChanges(
                    upserts: localUpserts,
                    deletions: localDeletions,
                    overrides: overridesApply
                )
            } catch {
                logger.error("Unable to apply iCloud profile changes locally: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard epoch == cycleEpoch, isSyncing else { return }

        // Build the new base per ID from the previous base: advance an entry
        // to the fetched remote version only when that version now lives
        // locally too (nothing was planned for the ID, or the planned upsert
        // applied). Keep the previous entry when a planned change did not
        // land — otherwise the next cycle would treat an unapplied remote
        // profile as synced and delete it from the cloud, or treat an
        // unapplied deletion as synced-away and resurrect the profile.
        // Confirmed push results below then add or remove entries on top.
        let plannedUpsertIDs = Set(localUpserts.map { $0.profile.id })
        let plannedDeletionIDs = Set(localDeletions.map { $0.id })
        let appliedUpsertIDs = applyResult?.appliedUpsertIDs ?? []
        let appliedDeletionIDs = applyResult?.appliedDeletionIDs ?? []

        var newBase = SyncBase(
            zoneGeneration: generation,
            profiles: [:],
            overridesUpdatedAt: base?.overridesUpdatedAt
        )
        let knownNames = Set(baseProfiles.keys)
            .union(remote.profiles.keys.map { $0.uuidString })
            .union(plannedUpsertIDs.map { $0.uuidString })
            .union(plannedDeletionIDs.map { $0.uuidString })
        for name in knownNames {
            guard let id = UUID(uuidString: name) else { continue }
            if appliedDeletionIDs.contains(id) {
                continue
            }
            if plannedDeletionIDs.contains(id) {
                newBase.profiles[name] = baseProfiles[name]
                continue
            }
            if let remoteEntry = remote.profiles[id],
               !plannedUpsertIDs.contains(id) || appliedUpsertIDs.contains(id) {
                newBase.profiles[name] = remoteEntry.profile
            } else {
                newBase.profiles[name] = baseProfiles[name]
            }
        }
        // Overrides follow the same rule: advance to the remote timestamp
        // only when no pull was planned or the pull was applied.
        if let remoteOverrides = remote.overrides,
           overridesApply == nil || applyResult?.overridesApplied == true {
            newBase.overridesUpdatedAt = remoteOverrides.updatedAt
        }
        if !remoteUpserts.isEmpty || !remoteDeletions.isEmpty {
            do {
                let (saveResults, deleteResults) = try await database.modifyRecords(
                    saving: remoteUpserts,
                    deleting: remoteDeletions,
                    savePolicy: .allKeys,
                    atomically: false
                )
                let localByID = Dictionary(uniqueKeysWithValues: local.profiles.map { ($0.id.uuidString, $0) })
                for (recordID, result) in saveResults {
                    switch result {
                    case .success:
                        if recordID == overridesRecordID {
                            newBase.overridesUpdatedAt = local.overridesUpdatedAt
                        } else if let profile = localByID[recordID.recordName] {
                            // Only confirmed uploads enter the base; a profile
                            // whose push failed stays out, so the next cycle
                            // still sees it as never-synced.
                            newBase.profiles[recordID.recordName] = profile
                        }
                    case .failure(let error):
                        logger.error("Unable to push record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
                for (recordID, result) in deleteResults {
                    switch result {
                    case .success:
                        newBase.profiles.removeValue(forKey: recordID.recordName)
                    case .failure(let error):
                        logger.error("Unable to delete record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                logger.error("Unable to push merged profile changes to iCloud: \(error.localizedDescription, privacy: .public)")
            }
        }


        // A stop or delete that landed during the awaits invalidates this
        // cycle's view; drop the result instead of rebasing.
        guard epoch == cycleEpoch, isSyncing else { return }
        base = newBase
        saveBase()

        if applyResult != nil {
            NotificationCenter.default.post(name: .profileSyncDidApplyRemoteChanges, object: nil)
        }
    }

    /// The zone vanished or its generation changed while this device held a
    /// base: another device deleted the iCloud data. Fall silent without
    /// touching local data, and silence the toggle without re-publishing.
    private func handleRemoteWipe() async {
        epoch &+= 1
        stopSync()
        clearBase()
        await MainActor.run {
            SettingsSyncController.shared.silenceProfilesSyncFromRemote()
        }
        logger.notice("The iCloud profile data was deleted elsewhere; profile sync silenced locally.")
    }

    private func claimZoneGeneration() async throws -> String {
        let generation = UUID().uuidString
        let record = CKRecord(recordType: RecordType.zoneInfo, recordID: zoneInfoRecordID)
        record[Field.generation] = generation
        let (saveResults, _) = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            // A fresh record carries no change tag, so this save succeeds
            // only when the zone-info record does not exist yet — an atomic
            // compare-and-set claim against a racing device.
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        for (_, result) in saveResults {
            try result.get()
        }
        return generation
    }

    // MARK: - CloudKit plumbing

    private struct RemoteProfileEntry {
        let profile: Profile
        let contents: String
    }

    private struct RemoteState {
        var profiles: [UUID: RemoteProfileEntry] = [:]
        var overrides: (value: ProxyOverrides, updatedAt: Date)?
        var zoneGeneration: String?
        /// The zone-info record exists but its generation cannot be read:
        /// unknown state, never a wipe.
        var zoneInfoUnreadable = false
        /// The overrides record exists but cannot be read: skip overrides
        /// decisions for the cycle instead of treating it as absent.
        var overridesUnreadable = false
        /// Record names (UUID strings) present in the zone but not decodable
        /// on this device — e.g. written by a newer app version.
        var undecodableRecordNames: Set<String> = []
    }

    /// Full zone state via recordZoneChanges with a nil token. Unlike
    /// CKQuery, this needs no schema indexes (a fresh Development container
    /// cannot even be queried) and is not backed by an eventually-consistent
    /// query index, so records saved moments ago are always visible.
    private func fetchRemoteState() async throws -> RemoteState {
        var state = RemoteState()

        // Full state: a nil token returns every record in the zone. Paginate
        // until moreComing is false so large zones are complete.
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            token = result.changeToken
            moreComing = result.moreComing
            for (recordID, changeResult) in result.modificationResultsByID {
                switch changeResult {
                case .success(let modification):
                    records.append(modification.record)
                case .failure:
                    // A fetch failure for a well-known record is unknown
                    // state, not absence: never mistake it for a wipe or a
                    // missing overrides record.
                    if recordID == zoneInfoRecordID {
                        state.zoneInfoUnreadable = true
                    } else if recordID == overridesRecordID {
                        state.overridesUnreadable = true
                    } else {
                        state.undecodableRecordNames.insert(recordID.recordName)
                    }
                }
            }
        }

        for record in records {
            switch record.recordType {
            case RecordType.profile:
                if let entry = Self.decodeProfileRecord(record) {
                    state.profiles[entry.profile.id] = entry
                } else {
                    state.undecodableRecordNames.insert(record.recordID.recordName)
                }
            case RecordType.overrides:
                if let overrides = Self.decodeOverridesRecord(record) {
                    state.overrides = overrides
                } else {
                    // Present but unreadable (e.g. written by a newer app
                    // version): skip overrides decisions this cycle.
                    state.overridesUnreadable = true
                }
            case RecordType.zoneInfo:
                if let generation = record[Field.generation] as? String {
                    state.zoneGeneration = generation
                } else {
                    state.zoneInfoUnreadable = true
                }
            default:
                continue
            }
        }
        return state
    }

    private func stagedProfile(
        _ profile: Profile,
        repository: SharedProfileRepository
    ) async -> (record: CKRecord, assetFile: URL?)? {
        do {
            let contents = try await repository.profileContents(for: profile.id)
            return try makeProfileRecord(profile: profile, contents: contents)
        } catch {
            logger.error("Unable to stage profile \(profile.id, privacy: .public) for sync: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func makeProfileRecord(profile: Profile, contents: String) throws -> (record: CKRecord, assetFile: URL?) {
        let record = CKRecord(
            recordType: RecordType.profile,
            recordID: CKRecord.ID(recordName: profile.id.uuidString, zoneID: zoneID)
        )
        record[Field.name] = profile.name
        record[Field.source] = profile.source.rawValue
        record[Field.remoteURL] = profile.remoteURL?.absoluteString
        record[Field.customUserAgent] = profile.customUserAgent
        record[Field.createdAt] = profile.createdAt
        record[Field.updatedAt] = profile.updatedAt
        record[Field.lastFetchedAt] = profile.lastFetchedAt
        record[Field.customOverridesEnabled] = profile.customOverridesEnabled ? 1 : 0
        record[Field.customOverrideYAML] = profile.customOverrideYAML
        if let subscriptionInfo = profile.subscriptionInfo {
            record[Field.subscriptionInfo] = try JSONEncoder().encode(subscriptionInfo)
        }

        // Unique per staging: overlapping pushes must not share the asset file
        // one of them deletes on completion.
        let assetFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("swihomo-sync-\(profile.id.uuidString)-\(UUID().uuidString).yaml")
        try contents.write(to: assetFile, atomically: true, encoding: .utf8)
        record[Field.contents] = CKAsset(fileURL: assetFile)
        return (record, assetFile)
    }

    private func makeOverridesRecord(_ overrides: ProxyOverrides, updatedAt: Date) throws -> CKRecord {
        // The controller secret is a per-device credential: strip it before
        // upload; applying devices keep their own.
        var sanitized = overrides
        sanitized.controllerSecret = ""
        let record = CKRecord(recordType: RecordType.overrides, recordID: overridesRecordID)
        record[Field.payload] = try JSONEncoder().encode(sanitized)
        record[Field.updatedAt] = updatedAt
        return record
    }

    private static func decodeProfileRecord(_ record: CKRecord) -> RemoteProfileEntry? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record[Field.name] as? String,
              let sourceRaw = record[Field.source] as? String,
              let source = ProfileSource(rawValue: sourceRaw),
              let createdAt = record[Field.createdAt] as? Date,
              let updatedAt = record[Field.updatedAt] as? Date,
              let asset = record[Field.contents] as? CKAsset,
              let assetURL = asset.fileURL,
              let contents = try? String(contentsOf: assetURL, encoding: .utf8) else {
            return nil
        }

        let subscriptionInfo = (record[Field.subscriptionInfo] as? Data).flatMap {
            try? JSONDecoder().decode(MihomoSubscriptionInfo.self, from: $0)
        }

        let profile = Profile(
            id: id,
            name: name,
            source: source,
            remoteURL: (record[Field.remoteURL] as? String).flatMap(URL.init(string:)),
            customUserAgent: record[Field.customUserAgent] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastFetchedAt: record[Field.lastFetchedAt] as? Date,
            subscriptionInfo: subscriptionInfo,
            customOverridesEnabled: (record[Field.customOverridesEnabled] as? Int ?? 1) != 0,
            customOverrideYAML: record[Field.customOverrideYAML] as? String ?? ""
        )
        return RemoteProfileEntry(profile: profile, contents: contents)
    }

    private static func decodeOverridesRecord(_ record: CKRecord) -> (value: ProxyOverrides, updatedAt: Date)? {
        guard let payload = record[Field.payload] as? Data,
              let value = try? JSONDecoder().decode(ProxyOverrides.self, from: payload),
              let updatedAt = record[Field.updatedAt] as? Date else {
            return nil
        }
        return (value, updatedAt)
    }

    // MARK: - Base persistence

    private var baseFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Swihomo", isDirectory: true)
            .appendingPathComponent("sync-base.json")
    }

    private func loadBase() {
        guard let url = baseFileURL,
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        base = try? decoder.decode(SyncBase.self, from: data)
    }

    private func saveBase() {
        guard let url = baseFileURL, let base else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(base)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            _ = Darwin.chmod(url.path, mode_t(0o600))
        } catch {
            logger.error("Unable to persist the profile sync base: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearBase() {
        base = nil
        if let url = baseFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Pending deletion flag

    private func isPendingZoneDeletion() -> Bool {
        UserDefaults.standard.bool(forKey: Self.pendingDeletionDefaultsKey)
    }

    private func pendingDeletionGeneration() -> String? {
        UserDefaults.standard.string(forKey: Self.pendingDeletionGenerationDefaultsKey)
    }

    private func setPendingZoneDeletion(_ pending: Bool, generation: String?) {
        UserDefaults.standard.set(pending, forKey: Self.pendingDeletionDefaultsKey)
        UserDefaults.standard.set(generation, forKey: Self.pendingDeletionGenerationDefaultsKey)
    }
}
