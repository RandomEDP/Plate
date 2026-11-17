import Foundation

/// Sharing a household through iCloud. The household is cut into small parts (one per recipe, kitchen item and
/// shopping list, one for the plan, one for the dashboard and so on), and each part is one record in iCloud. Two people
/// editing different recipes never get in each other's way; two people editing the same thing get the later edit.
///
/// This file is the pure side: cutting the household up, putting it back together, and working out what changed. The
/// app's `CloudSync` moves the parts to and from iCloud.
public enum HouseholdSync {
    /// What a part holds. A part's key is `kind` alone for one-off parts ("plan") or `kind.id` for one of many
    /// ("recipe.5F1C…", "extra.builtInPhotos", "photo.AB12….jpg").
    public enum Kind: String, CaseIterable, Sendable {
        case name, members, usage, hidden, plan, planSettings, stores, dashboard, extra, recipe, item, list, photo
    }

    /// Settings that belong to one phone, not the household: which AI to use goes with the Claude key, which is only
    /// in this phone's keychain.
    public static let localExtras: Set<String> = ["ai", "claudeModel"]

    /// How parts are written. Keys are sorted so the same value always gives the same bytes; dates are written the
    /// way the household file writes them, so a part read back from the file matches what was sent.
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Keys

    public static func key(_ kind: Kind, _ id: String? = nil) -> String {
        id.map { "\(kind.rawValue).\($0)" } ?? kind.rawValue
    }

    /// The kind and id of a key, or nil for a key this version of Plate doesn't know (from a newer Plate, say).
    public static func split(_ key: String) -> (kind: Kind, id: String?)? {
        if let dot = key.firstIndex(of: ".") {
            guard let kind = Kind(rawValue: String(key[..<dot])) else { return nil }
            let id = String(key[key.index(after: dot)...])
            return id.isEmpty ? nil : (kind, id)
        }
        return Kind(rawValue: key).map { ($0, nil) }
    }

    /// iCloud record names can't hold just anything, so a part whose key has other characters isn't shared.
    static func usable(_ key: String) -> Bool {
        !key.isEmpty && key.count < 200 && key.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        } && !key.hasPrefix("_")
    }

    // MARK: Cutting up and putting back

    /// Every part of the household that's shared, as bytes. The food log and this phone's own settings stay out.
    /// Photos appear as keys with no bytes; the picture itself travels separately.
    public static func parts(of h: Household) -> [String: Data] {
        let e = encoder
        var out: [String: Data] = [:]
        func put<T: Encodable>(_ key: String, _ value: T) {
            guard usable(key), let data = try? e.encode(value) else { return }
            out[key] = data
        }
        put(key(.name), h.name)
        put(key(.members), h.members)
        put(key(.usage), h.usage)
        put(key(.hidden), h.hiddenBuiltIns.map(\.uuidString).sorted())
        put(key(.plan), h.plan)
        put(key(.planSettings), h.planSettings)
        put(key(.stores), h.stores)
        put(key(.dashboard), h.dashboard)
        for (k, v) in h.extras where !localExtras.contains(k) { put(key(.extra, k), v) }
        for r in h.recipes { put(key(.recipe, r.id.uuidString), r) }
        for i in h.inventory { put(key(.item, i.id.uuidString), i) }
        for l in h.lists { put(key(.list, l.id.uuidString), l) }
        for f in h.photoFiles where usable(key(.photo, f)) { out[key(.photo, f)] = Data() }
        return out
    }

    /// Puts one part into the household. Gives false when the bytes can't be read (a part from a newer Plate), so
    /// nothing is changed.
    @discardableResult
    public static func apply(_ key: String, _ data: Data, to h: inout Household) -> Bool {
        guard let (kind, id) = split(key) else { return false }
        let d = decoder
        func read<T: Decodable>(_ type: T.Type) -> T? { try? d.decode(T.self, from: data) }
        switch kind {
        case .name: guard let v = read(String.self) else { return false }; h.name = v
        case .members: guard let v = read([Member].self) else { return false }; h.members = v
        case .usage: guard let v = read([UsageRecord].self) else { return false }; h.usage = v
        case .hidden: guard let v = read([String].self) else { return false }; h.hiddenBuiltIns = Set(v.compactMap(UUID.init(uuidString:)))
        case .plan: guard let v = read(MealPlan.self) else { return false }; h.plan = v
        case .planSettings: guard let v = read(PlanSettings.self) else { return false }; h.planSettings = v
        case .stores: guard let v = read([Store].self) else { return false }; h.stores = v
        case .dashboard: guard let v = read(HomeDashboard.self) else { return false }; h.dashboard = v
        case .extra:
            guard let id, !localExtras.contains(id), let v = read(String.self) else { return false }
            h.extras[id] = v
        case .recipe:
            guard let v = read(Recipe.self) else { return false }
            if let i = h.recipes.firstIndex(where: { $0.id == v.id }) { h.recipes[i] = v } else { h.recipes.append(v) }
        case .item:
            guard let v = read(InventoryItem.self) else { return false }
            if let i = h.inventory.firstIndex(where: { $0.id == v.id }) { h.inventory[i] = v } else { h.inventory.append(v) }
        case .list:
            guard let v = read(ShoppingList.self) else { return false }
            if let i = h.lists.firstIndex(where: { $0.id == v.id }) { h.lists[i] = v } else { h.lists.append(v) }
        case .photo:
            return true
        }
        return true
    }

    /// Takes out a part someone else deleted. One-off parts (the plan, the dashboard) are never deleted, only changed.
    public static func remove(_ key: String, from h: inout Household) {
        guard let (kind, id) = split(key), let id else { return }
        switch kind {
        case .extra: if !localExtras.contains(id) { h.extras[id] = nil }
        case .recipe: h.recipes.removeAll { $0.id.uuidString == id }
        case .item: h.inventory.removeAll { $0.id.uuidString == id }
        case .list: h.lists.removeAll { $0.id.uuidString == id }
        default: break
        }
    }

    /// The household as iCloud has it, keeping what's this phone's own from `local` (the food log, the AI setting).
    public static func assemble(_ cloud: [String: Data], keeping local: Household) -> Household {
        var h = local
        h.recipes = []; h.inventory = []; h.lists = []; h.usage = []; h.hiddenBuiltIns = []
        h.extras = local.extras.filter { localExtras.contains($0.key) }
        // Parts go in a fixed order so recipes, items and lists keep the same order on every phone.
        for key in cloud.keys.sorted() { apply(key, cloud[key]!, to: &h) }
        h.recipes.sort { $0.createdAt < $1.createdAt }
        h.inventory.sort { $0.addedAt < $1.addedAt }
        h.lists.sort { $0.createdAt < $1.createdAt }
        return h
    }

    /// What a phone ends up with when it joins a household that's already in iCloud (someone's invite, or the
    /// person's own iPad joining their iPhone): the shared household, plus any of this phone's recipes it doesn't
    /// already have. The kitchen, plan, lists and dashboard are the shared ones. The food log stays as it was.
    ///
    /// `me` is the person using this phone (their name and daily targets). Joining someone else's household adds
    /// them to it (`addMe`); a phone joining its owner's own iCloud becomes the person already there.
    public struct Joined: Sendable {
        public var household: Household
        public var broughtRecipes: Int
        /// Who this phone's person is in the joined household.
        public var me: UUID?
    }

    public static func join(local: Household, cloud: Household, me: UUID? = nil, addMe: Bool = false) -> Joined {
        var h = cloud
        h.log = local.log
        for k in localExtras { h.extras[k] = local.extras[k] }
        var brought = 0
        for r in local.recipes where !h.recipes.contains(where: { $0.id == r.id }) {
            if RecipeDuplicates.match(for: r, in: h.recipes) != nil { continue }
            h.recipes.append(r)
            brought += 1
        }
        var who = me
        if let mine = local.members.first(where: { $0.id == me }) ?? local.members.first, !h.members.contains(where: { $0.id == mine.id }) {
            if addMe { h.members.append(mine); who = mine.id } else { who = h.members.first?.id }
        } else if who == nil {
            who = addMe ? local.members.first?.id : h.members.first?.id
        }
        return Joined(household: h, broughtRecipes: brought, me: who)
    }

    // MARK: What changed

    /// The parts to send and the parts to delete, comparing what iCloud last had (`synced`) with the household now.
    /// Parts are compared by value, so a list whose ticked items come out in a different order isn't a change.
    public static func changes(from synced: [String: Data], to now: [String: Data]) -> (save: [String], delete: [String]) {
        let save = now.keys.filter { key in
            guard let old = synced[key] else { return true }
            return !same(key, old, now[key]!)
        }.sorted()
        let delete = synced.keys.filter { now[$0] == nil && split($0)?.id != nil }.sorted()
        return (save, delete)
    }

    /// True when two copies of a part say the same thing.
    public static func same(_ key: String, _ a: Data, _ b: Data) -> Bool {
        if a == b { return true }
        guard let x = value(key, a), let y = value(key, b) else { return false }
        return x == y
    }

    static func value(_ key: String, _ data: Data) -> AnyHashable? {
        guard let (kind, _) = split(key) else { return nil }
        let d = decoder
        func read<T: Decodable & Hashable>(_ type: T.Type) -> AnyHashable? { (try? d.decode(T.self, from: data)).map(AnyHashable.init) }
        switch kind {
        case .name, .extra: return read(String.self)
        case .members: return read([Member].self)
        case .usage: return (try? d.decode([UsageRecord].self, from: data)).map { AnyHashable(Set($0)) }
        case .hidden: return (try? d.decode([String].self, from: data)).map { AnyHashable(Set($0)) }
        case .plan: return read(MealPlan.self)
        case .planSettings: return read(PlanSettings.self)
        case .stores: return read([Store].self)
        case .dashboard: return read(HomeDashboard.self)
        case .recipe: return read(Recipe.self)
        case .item: return read(InventoryItem.self)
        case .list: return read(ShoppingList.self)
        case .photo: return AnyHashable(data)
        }
    }

    // MARK: Two edits at once

    /// When this phone's edit and someone else's meet: the food used is added together (both happened); for
    /// everything else this phone's edit wins, because it's the one being sent now.
    public static func resolve(_ key: String, mine: Data, theirs: Data) -> Data {
        guard split(key)?.kind == .usage else { return mine }
        let d = decoder
        let a = (try? d.decode([UsageRecord].self, from: mine)) ?? []
        let b = (try? d.decode([UsageRecord].self, from: theirs)) ?? []
        var seen = Set<UsageRecord>()
        let both = (a + b).filter { seen.insert($0).inserted }.sorted { $0.date < $1.date }
        return (try? encoder.encode(both)) ?? mine
    }
}

extension HouseholdSync {
    /// One part of the household as it is now, or nil when it isn't there (or isn't shared).
    public static func part(_ key: String, of h: Household) -> Data? {
        guard let (kind, id) = split(key) else { return nil }
        let e = encoder
        func enc<T: Encodable>(_ v: T?) -> Data? { v.flatMap { try? e.encode($0) } }
        switch kind {
        case .name: return enc(h.name)
        case .members: return enc(h.members)
        case .usage: return enc(h.usage)
        case .hidden: return enc(h.hiddenBuiltIns.map(\.uuidString).sorted())
        case .plan: return enc(h.plan)
        case .planSettings: return enc(h.planSettings)
        case .stores: return enc(h.stores)
        case .dashboard: return enc(h.dashboard)
        case .extra: return id.flatMap { localExtras.contains($0) ? nil : enc(h.extras[$0]) }
        case .recipe: return enc(h.recipes.first { $0.id.uuidString == id })
        case .item: return enc(h.inventory.first { $0.id.uuidString == id })
        case .list: return enc(h.lists.first { $0.id.uuidString == id })
        case .photo: return id.flatMap { h.photoFiles.contains($0) ? Data() : nil }
        }
    }
}

/// What this phone knows iCloud holds, kept between launches so only real changes are sent.
public struct SyncLedger: Codable, Hashable, Sendable {
    /// Each part as iCloud last had it, as far as this phone knows.
    public var synced: [String: Data]
    /// Parts this version of Plate couldn't read (from a newer Plate). They're left alone, never deleted.
    public var unreadable: Set<String>
    /// True once the household already in iCloud (if there was one) has been folded in.
    public var joined: Bool

    public init(synced: [String: Data] = [:], unreadable: Set<String> = [], joined: Bool = false) {
        self.synced = synced; self.unreadable = unreadable; self.joined = joined
    }

    /// The parts to send and delete since last time, noted as sent.
    public mutating func take(_ h: Household) -> (save: [String], delete: [String]) {
        let now = HouseholdSync.parts(of: h)
        var (save, delete) = HouseholdSync.changes(from: synced, to: now)
        delete.removeAll { unreadable.contains($0) }
        for k in save { synced[k] = now[k] }
        for k in delete { synced[k] = nil }
        return (save, delete)
    }

    /// The first time this phone syncs: when iCloud already has a household, this phone takes it (keeping its own
    /// food log and any recipes the household doesn't have yet); when iCloud is empty, this phone's household is sent.
    public mutating func join(_ local: Household, cloud: [String: Data], me: UUID? = nil, addMe: Bool = false) -> HouseholdSync.Joined {
        joined = true
        guard !cloud.isEmpty else {
            synced = [:]
            return HouseholdSync.Joined(household: local, broughtRecipes: 0, me: me ?? local.members.first?.id)
        }
        let shared = HouseholdSync.assemble(cloud, keeping: local)
        synced = cloud
        unreadable = Set(cloud.compactMap { key, data in
            var probe = Household()
            return HouseholdSync.split(key) == nil || HouseholdSync.apply(key, data, to: &probe) ? nil : key
        })
        return HouseholdSync.join(local: local, cloud: shared, me: me, addMe: addMe)
    }

    /// A part arrived from iCloud. `pending` is true when this phone has an edit to it waiting to go. Gives true when
    /// the household changed.
    @discardableResult
    public mutating func receive(_ key: String, _ data: Data, into h: inout Household, pending: Bool) -> Bool {
        let before = synced[key]
        synced[key] = data
        guard HouseholdSync.split(key) != nil else { unreadable.insert(key); return false }
        // An edit here that hasn't gone yet (or hasn't even been noted yet) beats the one that arrived, except for
        // food used, where both count.
        let mine = HouseholdSync.part(key, of: h)
        let editedHere = pending || (mine != nil && before.map { !HouseholdSync.same(key, $0, mine!) } ?? false)
        if editedHere, let mine {
            let merged = HouseholdSync.resolve(key, mine: mine, theirs: data)
            if merged == mine { return false }
            return HouseholdSync.apply(key, merged, to: &h)
        }
        guard HouseholdSync.apply(key, data, to: &h) else { unreadable.insert(key); return false }
        unreadable.remove(key)
        if let now = HouseholdSync.part(key, of: h) { synced[key] = now }
        return true
    }

    /// A part was deleted in iCloud (someone used up an item, deleted a recipe). Deleting wins over an edit here.
    @discardableResult
    public mutating func receiveDeletion(_ key: String, into h: inout Household) -> Bool {
        synced[key] = nil
        unreadable.remove(key)
        guard HouseholdSync.part(key, of: h) != nil else { return false }
        HouseholdSync.remove(key, from: &h)
        return true
    }
}
