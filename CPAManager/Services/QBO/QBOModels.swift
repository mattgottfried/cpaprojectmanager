import Foundation

/// Which QuickBooks Online API host to talk to. Matt's Intuit developer app has
/// separate sandbox and production credentials/company files.
enum QBOEnvironment: String, CaseIterable, Identifiable, Codable {
    case sandbox
    case production

    var id: String { rawValue }
    var label: String { self == .sandbox ? "Sandbox" : "Production" }

    var apiBaseURL: String {
        switch self {
        case .sandbox:    return "https://sandbox-quickbooks.api.intuit.com"
        case .production: return "https://quickbooks.api.intuit.com"
        }
    }
}

enum QBOClientError: LocalizedError {
    case notAuthorized
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Not connected to QuickBooks."
        case .http(let code, let message):
            return code == 0 ? message : "QuickBooks error (\(code)): \(message)"
        case .decoding:
            return "Unexpected response from QuickBooks."
        }
    }
}

// MARK: - OAuth

struct QBOTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

// MARK: - Customer

struct QBOCustomer: Decodable {
    let Id: String?
    let DisplayName: String
}

struct QBOCustomerQueryResponse: Decodable {
    struct Body: Decodable { let Customer: [QBOCustomer]? }
    let QueryResponse: Body
}

struct QBOCustomerCreateResponse: Decodable {
    let Customer: QBOCustomer
}

// MARK: - Item (service line item) & Account

struct QBOItem: Decodable {
    let Id: String?
    let Name: String
}

struct QBOItemQueryResponse: Decodable {
    struct Body: Decodable { let Item: [QBOItem]? }
    let QueryResponse: Body
}

struct QBOItemCreateResponse: Decodable {
    let Item: QBOItem
}

struct QBOAccount: Decodable {
    let Id: String
    let Name: String
}

struct QBOAccountQueryResponse: Decodable {
    struct Body: Decodable { let Account: [QBOAccount]? }
    let QueryResponse: Body
}

// MARK: - Invoice (request payload + create response)

struct QBOInvoiceRequest: Encodable {
    struct Ref: Encodable { let value: String }
    struct SalesItemLineDetail: Encodable {
        let ItemRef: Ref
        let Qty: Double
        let UnitPrice: Double
    }
    struct Line: Encodable {
        let Amount: Double
        let DetailType: String
        let Description: String
        let SalesItemLineDetail: SalesItemLineDetail
    }

    let CustomerRef: Ref
    let DocNumber: String
    let TxnDate: String
    let DueDate: String
    let Line: [Line]
    let PrivateNote: String
}

struct QBOInvoiceCreateResponse: Decodable {
    struct QBOInvoiceID: Decodable { let Id: String }
    let Invoice: QBOInvoiceID
}
