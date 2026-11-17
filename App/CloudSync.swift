import CloudKit
import Foundation
import Observation
import PlateCore
import UIKit

/// Shares the household through iCloud. Everyone in a household sees the same kitchen, recipes, plan, shopping lists
/// and dashboard; each phone keeps its own food log and AI setting.
///
/// The household lives in one iCloud zone ("Household") in the owner's iCloud, one record per part (see
/// `HouseholdSync`). The owner's own devices (iPhone and the wall iPad) sync through it straight away. Inviting someone
/// shares the whole zone with them (a CKShare link sent from the share sheet); their phone then syncs with the
/// owner's zone instead of its own. Apple's CKSyncEngine does the sending and fetching and retries when offline.
@MainActor
@Observable
final class CloudSync {
    static let containerID = "iCloud.com.randomedp.plate"
    static let zoneName = "Household"
    static let recordType = "PlateItem"
    /// The sync object, for the scene delegate to hand invites to.
    static weak var current: CloudSync?

    enum Status: Equatable {
        case off, starting, noAccount, upToDate(Date), working, problem(String)
    }

    /// Whose household this phone is in.
    enum Scope: Codable, Equatable {
        /// This person's own, in their iCloud (shared with others or not).
        case own
        /// Someone else's, joined from an invite. `ownerName` is iCloud's id for the owner, `ownerTitle` their name.
        case joined(ownerName: String, ownerTitle: String)
    }

    /// Everything kept between launches.
    struct Stored: Codable {
        var scope: Scope = .own
        var engine: CKSyncEngine.State.Serialization?
        var ledger = SyncLedger()
        /// Each record's iCloud bookkeeping (its change tag), so saves don't trip over themselves.
        var systemFields: [String: Data] = [:]
        var zoneMade = false
    }

    private(set) var status: Status = .starting
    /// People the household is shared with (the owner sees them), or the owner (for someone who joined).
    private(set) var people: [String] = []
    private(set) var isShared = false
    var scope: Scope { stored.scope }
    /// An invite that's arrived and is waiting for the person to say yes.
    var invite: CKShare.Metadata?

    /// Sharing can be turned off on one device (Settings). It's on unless turned off.
    var enabled = !UserDefaults.standard.bool(forKey: "cloudSyncOff") {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(!enabled, forKey: "cloudSyncOff")
            if enabled { Task { await start() } } else { stop(); status = .off }
        }
    }

    private let model: AppModel
    private let container = CKContainer(identifier: CloudSync.containerID)
    private var stored: Stored
    private var engine: CKSyncEngine?
    private var fetching = false
    /// Records fetched before this phone has joined (folded in all at once by `finishJoining`).
    private var firstFetch: [String: Data] = [:]
    private var poll: Task<Void, Never>?

    private static var fileURL: URL { SharedStorage.folder.appendingPathComponent("cloud-sync.json") }
    private static var outbox: URL { FileManager.default.temporaryDirectory.appendingPathComponent("PlateOutbox", isDirectory: true) }

    init(model: AppModel) {
        self.model = model
        stored = (try? Data(contentsOf: CloudSync.fileURL)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        CloudSync.current = self
        model.afterChange = { [weak self] in self?.householdChanged() }
    }

    var zoneID: CKRecordZone.ID {
        switch stored.scope {
        case .own: return CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: CKCurrentUserDefaultName)
        case .joined(let owner, _): return CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: owner)
        }
    }

    private var database: CKDatabase {
        stored.scope == .own ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    // MARK: Starting and stopping

    private var isStarting = false

    func start() async {
        guard enabled else { status = .off; return }
        guard engine == nil else { await refresh(); return }
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        status = .starting
        let account = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard account == .available else {
            status = account == .temporarilyUnavailable || account == .couldNotDetermine
                ? .problem("iCloud isn't ready on this device yet. Plate will try again when you next open it.")
                : .noAccount
            return
        }
        var config = CKSyncEngine.Configuration(database: database, stateSerialization: stored.engine, delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if stored.scope == .own && !stored.zoneMade {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        if !stored.ledger.joined {
            status = .working
            firstFetch = [:]
            do {
                try await engine.fetchChanges()
                finishJoining()
            } catch {
                status = .problem(CloudSync.explain(error))
            }
        } else {
            await refresh()
        }
        startPolling()
        await loadPeople()
    }

    func stop() {
        poll?.cancel()
        poll = nil
        engine = nil
    }

    /// Fetches anything new and sends anything waiting. Called when the app comes to the front.
    func refresh() async {
        guard let engine, stored.ledger.joined else { return }
        do {
            try await engine.fetchChanges()
            householdChanged()
            try await engine.sendChanges()
            status = .upToDate(Date())
        } catch {
            status = .problem(CloudSync.explain(error))
        }
    }

    /// Without push notifications, other people's changes are fetched every 20 seconds while Plate is open, so the
    /// wall iPad keeps up.
    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled else { return }
                if UIApplication.shared.applicationState == .active { await self.refresh() }
            }
        }
    }

    /// The first fetch is done: fold the household that's in iCloud into this phone's, or send this phone's up.
    private func finishJoining() {
        let joiningSomeone = stored.scope != .own
        let joined = stored.ledger.join(model.household, cloud: firstFetch, me: model.meID, addMe: joiningSomeone)
        firstFetch = [:]
        if joined.household != model.household { model.household = joined.household }
        if let me = joined.me { model.meID = me }
        save()
        householdChanged()
        status = .upToDate(Date())
        if joiningSomeone {
            let brought = joined.broughtRecipes
            model.banner = brought == 0 ? "You've joined the household"
                : "You've joined the household and brought \(brought) recipe\(brought == 1 ? "" : "s")"
        }
    }

    // MARK: Local changes

    /// The household changed on this phone (or something arrived): note what needs sending.
    func householdChanged() {
        guard let engine, stored.ledger.joined, !fetching else { return }
        let (saves, deletes) = stored.ledger.take(model.household)
        guard !saves.isEmpty || !deletes.isEmpty else { return }
        let zone = zoneID
        engine.state.add(pendingRecordZoneChanges:
            saves.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: zone)) }
            + deletes.map { .deleteRecord(CKRecord.ID(recordName: $0, zoneID: zone)) })
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(stored)
            try data.write(to: CloudSync.fileURL, options: .atomic)
        } catch {
            print("Plate couldn't save its iCloud notes: \(error)")
        }
    }

    // MARK: Records

    /// The record to send for a part, or nil when the part has gone (it was deleted since).
    fileprivate func record(for id: CKRecord.ID) -> CKRecord? {
        let key = id.recordName
        guard let data = HouseholdSync.part(key, of: model.household) else { return nil }
        let record = stored.systemFields[key].flatMap(CloudSync.unarchive) ?? CKRecord(recordType: CloudSync.recordType, recordID: id)
        if HouseholdSync.split(key)?.kind == .photo, let file = HouseholdSync.split(key)?.id {
            let url = DishPhotos.folder.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            record["file"] = CKAsset(fileURL: url)
            record["data"] = nil
        } else if data.count > 700_000 {
            // Records hold up to 1 MB; anything near that goes as a file.
            let url = CloudSync.outbox.appendingPathComponent(key + ".json")
            try? FileManager.default.createDirectory(at: CloudSync.outbox, withIntermediateDirectories: true)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            record["file"] = CKAsset(fileURL: url)
            record["data"] = nil
        } else {
            record["data"] = data
            record["file"] = nil
        }
        return record
    }

    private static func data(of record: CKRecord) -> Data? {
        if let d = record["data"] as? Data { return d }
        if let url = (record["file"] as? CKAsset)?.fileURL { return try? Data(contentsOf: url) }
        return nil
    }

    private static func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: What the engine tells us

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let e):
            stored.engine = e.stateSerialization
            save()

        case .accountChange(let e):
            switch e.changeType {
            case .signIn:
                Task { await self.start() }
            case .signOut, .switchAccounts:
                // A different iCloud account: start again from this phone's household, as if new.
                stop()
                stored = Stored()
                save()
                status = .noAccount
            @unknown default:
                break
            }

        case .willFetchChanges:
            fetching = true
            if stored.ledger.joined { status = .working }

        case .didFetchChanges:
            fetching = false
            if stored.ledger.joined {
                householdChanged()
                status = .upToDate(Date())
            }

        case .fetchedDatabaseChanges(let e):
            for deletion in e.deletions where deletion.zoneID == zoneID {
                householdGone()
            }

        case .fetchedRecordZoneChanges(let e):
            receive(e)

        case .sentDatabaseChanges(let e):
            if e.savedZones.contains(where: { $0.zoneID == zoneID }) { stored.zoneMade = true; save() }

        case .sentRecordZoneChanges(let e):
            sent(e)

        default:
            break
        }
    }

    private func receive(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        let zone = zoneID
        let pending = Set(engine?.state.pendingRecordZoneChanges.compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName }
            return nil
        } ?? [])
        var h = model.household
        var changed = false
        for mod in e.modifications where mod.record.recordID.zoneID == zone {
            let record = mod.record
            let key = record.recordID.recordName
            stored.systemFields[key] = CloudSync.archive(record)
            if HouseholdSync.split(key)?.kind == .photo, let file = HouseholdSync.split(key)?.id {
                keepPhoto(record, as: file)
            }
            guard let data = CloudSync.data(of: record) else { continue }
            if !stored.ledger.joined {
                firstFetch[key] = data
            } else if stored.ledger.receive(key, data, into: &h, pending: pending.contains(key)) {
                changed = true
            }
        }
        for deletion in e.deletions where deletion.recordID.zoneID == zone {
            let key = deletion.recordID.recordName
            stored.systemFields[key] = nil
            if !stored.ledger.joined {
                firstFetch[key] = nil
            } else if stored.ledger.receiveDeletion(key, into: &h) {
                changed = true
            }
        }
        if changed { model.household = h }
        save()
    }

    /// A dish photo arrived: copy it in beside the others, unless it's already here.
    private func keepPhoto(_ record: CKRecord, as file: String) {
        let target = DishPhotos.folder.appendingPathComponent(file)
        guard !FileManager.default.fileExists(atPath: target.path),
              let source = (record["file"] as? CKAsset)?.fileURL else { return }
        try? FileManager.default.createDirectory(at: DishPhotos.folder, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    private func sent(_ e: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in e.savedRecords {
            stored.systemFields[record.recordID.recordName] = CloudSync.archive(record)
        }
        for id in e.deletedRecordIDs { stored.systemFields[id.recordName] = nil }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var h = model.household
        var changed = false
        for failure in e.failedRecordSaves {
            let id = failure.record.recordID
            let key = id.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                // Someone else saved it first. Food used is added together; otherwise this phone's edit goes again.
                if let server = failure.error.serverRecord {
                    stored.systemFields[key] = CloudSync.archive(server)
                    if let theirs = CloudSync.data(of: server), let mine = HouseholdSync.part(key, of: h) {
                        let merged = HouseholdSync.resolve(key, mine: mine, theirs: theirs)
                        if merged != mine, HouseholdSync.apply(key, merged, to: &h) { changed = true }
                    }
                }
                retry.append(.saveRecord(id))
            case .zoneNotFound:
                if stored.scope == .own {
                    stored.zoneMade = false
                    engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    retry.append(.saveRecord(id))
                } else {
                    householdGone()
                    return
                }
            case .unknownItem:
                // It was deleted in iCloud; the deletion arrives with the next fetch and wins.
                stored.systemFields[key] = nil
            case .quotaExceeded:
                status = .problem("Your iCloud storage is full, so changes aren't being shared. Free some space in Settings → iCloud.")
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated:
                break // The engine tries these again by itself.
            case .permissionFailure:
                status = .problem("You can only look at this household, not change it. Ask its owner to let you make changes.")
            default:
                status = .problem(CloudSync.explain(failure.error))
            }
        }
        if !retry.isEmpty { engine?.state.add(pendingRecordZoneChanges: retry) }
        if changed { model.household = h }
        save()
    }

    // MARK: Sharing

    /// The household's share, if it has one.
    private func fetchShare() async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await database.record(for: id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Makes (or finds) the household's share, ready for the invite sheet. Everything waiting is sent first, so the
    /// person invited sees the whole household.
    func shareForInvite() async throws -> CKShare {
        guard let engine else { throw CloudSyncError.notRunning }
        try await engine.sendChanges()
        if let share = try await fetchShare() { return share }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = model.household.name as CKRecordValue
        share.publicPermission = .none
        let (saved, _) = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if case .failure(let error)? = saved[share.recordID] { throw error }
        isShared = true
        return share
    }

    var containerForSharing: CKContainer { container }

    /// Who's in the household, for Settings.
    func loadPeople() async {
        guard engine != nil, let share = try? await fetchShare() else {
            isShared = stored.scope != .own
            people = []
            return
        }
        let me = share.currentUserParticipant
        people = share.participants
            .filter { $0 != me && $0.acceptanceStatus != .removed }
            .map { p in
                let name = p.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                return (name?.isEmpty == false ? name! : p.userIdentity.lookupInfo?.emailAddress ?? "Someone")
                    + (p.acceptanceStatus == .pending ? " (invited)" : "")
            }
        isShared = stored.scope != .own || share.participants.count > 1
    }

    /// An invite link was opened. Plate asks before joining (see `RootView`).
    func received(_ metadata: CKShare.Metadata) {
        if metadata.participantRole == .owner {
            model.banner = "That's your own household's invite"
            return
        }
        invite = metadata
    }

    /// Joins the household the invite is for. This phone's kitchen, plan, lists and dashboard are swapped for the
    /// shared ones; its recipes come along. What was here stays in this person's own iCloud, and comes back if they leave.
    func accept(_ metadata: CKShare.Metadata) async {
        invite = nil
        status = .working
        do {
            _ = try await container.accept(metadata)
        } catch {
            status = .problem("Plate couldn't join that household: \(CloudSync.explain(error))")
            return
        }
        // Anything waiting for the old household goes first.
        try? await engine?.sendChanges()
        let owner = metadata.share.recordID.zoneID.ownerName
        let title = metadata.ownerIdentity.nameComponents
            .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? "Someone"
        stop()
        stored = Stored(scope: .joined(ownerName: owner, ownerTitle: title.isEmpty ? "Someone" : title))
        save()
        await start()
    }

    /// Leaves someone else's household. This phone keeps a copy of everything, then goes back to its own iCloud
    /// household (which still has what was there before joining).
    func leave() async {
        guard case .joined = stored.scope else { return }
        do {
            try await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // Already gone.
        } catch {
            status = .problem("Plate couldn't leave the household: \(CloudSync.explain(error))")
            return
        }
        backToOwn(message: "You've left the household. Everything that was in it is still on this phone.")
    }

    /// The shared household has gone: its owner stopped sharing, or took this person out.
    private func householdGone() {
        guard case .joined(_, let owner) = stored.scope else {
            // Our own zone was deleted (iCloud data reset): send everything again.
            stored.ledger = SyncLedger(joined: true)
            stored.systemFields = [:]
            stored.zoneMade = false
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            householdChanged()
            return
        }
        backToOwn(message: "\(owner) stopped sharing the household. Everything that was in it is still on this phone.")
    }

    private func backToOwn(message: String) {
        stop()
        stored = Stored()
        save()
        people = []
        isShared = false
        model.banner = message
        Task { await start() }
    }

    func reportShareProblem(_ error: Error) {
        status = .problem("The invite couldn't be saved: \(CloudSync.explain(error))")
    }

    static func explain(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings to share the household."
        case .networkFailure, .networkUnavailable: return "No internet just now. Changes will be shared when you're back online."
        case .quotaExceeded: return "Your iCloud storage is full. Free some space in Settings → iCloud."
        case .badContainer, .missingEntitlement: return "Plate's iCloud container isn't set up yet."
        case .serverRejectedRequest: return "iCloud turned the change down. Plate's iCloud setup may not be finished yet."
        default: return ck.localizedDescription
        }
    }
}

enum CloudSyncError: LocalizedError {
    case notRunning
    var errorDescription: String? { "iCloud sharing isn't running. Check you're signed in to iCloud and sharing is on in Settings." }
}

// MARK: - CKSyncEngine's delegate

extension CloudSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run {
            // Events from an engine that's since been stopped (after joining or leaving) are for the old household.
            guard syncEngine === self.engine else { return }
            self.handle(event)
        }
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                               syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        guard await MainActor.run(body: { syncEngine === self.engine }) else { return nil }
        // Records are made on the main actor (that's where the household is), then handed over.
        let records: [CKRecord.ID: CKRecord] = await MainActor.run {
            var out: [CKRecord.ID: CKRecord] = [:]
            var gone: [CKSyncEngine.PendingRecordZoneChange] = []
            for change in changes {
                guard case .saveRecord(let id) = change else { continue }
                if let r = self.record(for: id) { out[id] = r } else { gone.append(change) }
            }
            if !gone.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: gone) }
            return out
        }
        let wanted = changes.filter {
            if case .saveRecord(let id) = $0 { return records[id] != nil }
            return true
        }
        guard !wanted.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: wanted) { records[$0] }
    }
}
