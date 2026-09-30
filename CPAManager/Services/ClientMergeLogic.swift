import Foundation

// Pure duplicate-client detection for the Sync Health screen. Two devices that each added
// the same person (or a first sync that unioned sample data) leave look-alike clients.

struct DupClientInput: Equatable {
    var id: UUID
    var name: String
    var company: String
    var email: String
    var createdAt: Date
    /// Jobs + invoices + interactions + documents: the more, the more likely it's the one to keep.
    var recordCount: Int
}

struct DupGroup: Equatable, Identifiable {
    var keeper: UUID
    var others: [UUID]
    var reason: String
    var id: UUID { keeper }
}

enum DuplicateClients {
    private static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Groups clients that share a name (and company) or an email address. In each group the
    /// client with the most records is kept, then the oldest.
    static func groups(_ clients: [DupClientInput]) -> [DupGroup] {
        var parent = Array(0..<clients.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root { let next = parent[node]; parent[node] = root; node = next }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        var byName: [String: Int] = [:]
        var byEmail: [String: Int] = [:]
        var reasons: [Int: Set<String>] = [:]
        for (index, client) in clients.enumerated() {
            let name = normalized(client.name)
            if !name.isEmpty {
                let key = name + "|" + normalized(client.company)
                if let first = byName[key] { union(first, index); reasons[first, default: []].insert("Same name"); reasons[index, default: []].insert("Same name") }
                else { byName[key] = index }
            }
            let email = client.email.trimmingCharacters(in: .whitespaces).lowercased()
            if !email.isEmpty {
                if let first = byEmail[email] { union(first, index); reasons[first, default: []].insert("Same email"); reasons[index, default: []].insert("Same email") }
                else { byEmail[email] = index }
            }
        }

        var members: [Int: [Int]] = [:]
        for index in clients.indices { members[find(index), default: []].append(index) }

        var result: [DupGroup] = []
        for (_, indices) in members where indices.count > 1 {
            let sorted = indices.sorted { a, b in
                let ca = clients[a], cb = clients[b]
                if ca.recordCount != cb.recordCount { return ca.recordCount > cb.recordCount }
                if ca.createdAt != cb.createdAt { return ca.createdAt < cb.createdAt }
                return ca.id.uuidString < cb.id.uuidString
            }
            let why = indices.reduce(into: Set<String>()) { $0.formUnion(reasons[$1] ?? []) }
            result.append(DupGroup(keeper: clients[sorted[0]].id, others: sorted.dropFirst().map { clients[$0].id },
                                   reason: why.sorted().joined(separator: " and ")))
        }
        return result.sorted { $0.keeper.uuidString < $1.keeper.uuidString }
    }
}
