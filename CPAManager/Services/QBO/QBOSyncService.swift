import Foundation
import SwiftData

/// Orchestrates pushing an invoice to QuickBooks Online: ensures a matching
/// Customer and a "Accounting Services" line item exist, then creates the
/// Invoice. Updates the invoice's sync state/error in place.
enum QBOSyncService {
    private static let serviceItemName = "Accounting Services"

    static func send(invoice: Invoice, auth: QBOAuthService, context: ModelContext) async {
        do {
            let (token, realmID) = try await auth.validAccessToken()
            let qbo = QBOClient(environment: auth.environment, realmID: realmID, accessToken: token)

            guard let client = invoice.client else {
                throw QBOClientError.http(0, "This invoice has no client.")
            }

            let customerID = try await ensureCustomer(client, qbo: qbo)
            client.qboCustomerId = customerID

            let itemID = try await ensureServiceItem(qbo: qbo)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let lines: [QBOInvoiceRequest.Line] = invoice.lineList.map { line in
                QBOInvoiceRequest.Line(
                    Amount: line.amount,
                    DetailType: "SalesItemLineDetail",
                    Description: line.detail,
                    SalesItemLineDetail: .init(ItemRef: .init(value: itemID), Qty: line.quantity, UnitPrice: line.rate)
                )
            }

            let body = QBOInvoiceRequest(
                CustomerRef: .init(value: customerID),
                DocNumber: invoice.displayNumber,
                TxnDate: dateFormatter.string(from: invoice.issueDate),
                DueDate: dateFormatter.string(from: invoice.dueDate),
                Line: lines,
                PrivateNote: invoice.notes
            )

            let response = try await qbo.create("invoice", body: body, as: QBOInvoiceCreateResponse.self)

            invoice.qboId = response.Invoice.Id
            invoice.qboSyncState = .synced
            invoice.qboSyncError = ""
        } catch {
            invoice.qboSyncState = .failed
            invoice.qboSyncError = error.localizedDescription
        }
        try? context.save()
    }

    private static func ensureCustomer(_ client: Client, qbo: QBOClient) async throws -> String {
        if !client.qboCustomerId.isEmpty {
            return client.qboCustomerId
        }

        let escapedName = client.displayName.replacingOccurrences(of: "'", with: "\\'")
        let result = try await qbo.query(
            "SELECT * FROM Customer WHERE DisplayName = '\(escapedName)'",
            as: QBOCustomerQueryResponse.self
        )
        if let existing = result.QueryResponse.Customer?.first, let id = existing.Id {
            return id
        }

        struct CreateBody: Encodable {
            struct Email: Encodable { let Address: String }
            let DisplayName: String
            let PrimaryEmailAddr: Email?
        }
        let body = CreateBody(
            DisplayName: client.displayName,
            PrimaryEmailAddr: client.email.isEmpty ? nil : .init(Address: client.email)
        )
        let created = try await qbo.create("customer", body: body, as: QBOCustomerCreateResponse.self)
        guard let id = created.Customer.Id else { throw QBOClientError.decoding }
        return id
    }

    private static func ensureServiceItem(qbo: QBOClient) async throws -> String {
        let result = try await qbo.query(
            "SELECT * FROM Item WHERE Name = '\(serviceItemName)'",
            as: QBOItemQueryResponse.self
        )
        if let existing = result.QueryResponse.Item?.first, let id = existing.Id {
            return id
        }

        let accounts = try await qbo.query(
            "SELECT * FROM Account WHERE AccountType = 'Income' MAXRESULTS 1",
            as: QBOAccountQueryResponse.self
        )
        guard let incomeAccount = accounts.QueryResponse.Account?.first else {
            throw QBOClientError.http(0, "No income account found in QuickBooks to attach the service item to.")
        }

        struct CreateBody: Encodable {
            struct Ref: Encodable { let value: String }
            let Name: String
            let `Type`: String
            let IncomeAccountRef: Ref
        }
        let body = CreateBody(Name: serviceItemName, Type: "Service", IncomeAccountRef: .init(value: incomeAccount.Id))
        let created = try await qbo.create("item", body: body, as: QBOItemCreateResponse.self)
        guard let id = created.Item.Id else { throw QBOClientError.decoding }
        return id
    }
}
