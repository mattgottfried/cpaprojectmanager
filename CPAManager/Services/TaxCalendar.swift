import Foundation

/// Federal filing deadlines for calendar-year clients, by entity type.
///
/// Due dates (verified against IRS-based sources — see README):
/// - Form 1040, 1120: April 15 · extended October 15
/// - Form 1065, 1120-S: March 15 · extended September 15
/// - Form 1041: April 15 · extended September 30
/// - Form 990: May 15 · extended November 15
/// - Individual estimated payments: April 15, June 15, September 15, January 15
///
/// A date that lands on a weekend or legal holiday moves to the next business day.
/// Only the holidays that can actually collide with these dates are modelled
/// (Martin Luther King Jr. Day and Washington, D.C. Emancipation Day). Fiscal-year
/// entities, disaster-relief postponements and state deadlines are not covered —
/// always confirm against the IRS calendar for the year.
enum TaxCalendar {
    enum Form: String, CaseIterable {
        case f1040, f1120S, f1065, f1120, f1041, f990

        var label: String {
            switch self {
            case .f1040:  return "Form 1040"
            case .f1120S: return "Form 1120-S"
            case .f1065:  return "Form 1065"
            case .f1120:  return "Form 1120"
            case .f1041:  return "Form 1041"
            case .f990:   return "Form 990"
            }
        }
    }

    enum Kind: String {
        case filing, extended, estimatedPayment
    }

    struct Deadline: Equatable, Identifiable {
        var title: String
        var date: Date
        var kind: Kind
        var taxYear: Int
        var id: String { "\(kind.rawValue)-\(title)-\(taxYear)" }
    }

    static func form(for entity: EntityType) -> Form? {
        switch entity {
        case .individual1040:  return .f1040
        case .sCorp1120S:      return .f1120S
        case .partnership1065: return .f1065
        case .cCorp1120:       return .f1120
        case .trust1041:       return .f1041
        case .nonProfit990:    return .f990
        case .other:           return nil
        }
    }

    /// (month, day) of the original and extended due dates, in the year *after* the tax year.
    private static func monthDay(_ form: Form, extended: Bool) -> (month: Int, day: Int) {
        switch (form, extended) {
        case (.f1040, false), (.f1120, false), (.f1041, false): return (4, 15)
        case (.f1040, true), (.f1120, true):                     return (10, 15)
        case (.f1065, false), (.f1120S, false):                  return (3, 15)
        case (.f1065, true), (.f1120S, true):                    return (9, 15)
        case (.f1041, true):                                     return (9, 30)
        case (.f990, false):                                     return (5, 15)
        case (.f990, true):                                      return (11, 15)
        }
    }

    static func dueDate(form: Form, taxYear: Int, extended: Bool, calendar: Calendar = .current) -> Date {
        let md = monthDay(form, extended: extended)
        let raw = calendar.date(from: DateComponents(year: taxYear + 1, month: md.month, day: md.day)) ?? .now
        return nextBusinessDay(onOrAfter: raw, calendar: calendar)
    }

    /// April 15, June 15, September 15 of `taxYear`, and January 15 of the next year.
    static func estimatedPaymentDates(taxYear: Int, calendar: Calendar = .current) -> [Date] {
        let parts = [(taxYear, 4), (taxYear, 6), (taxYear, 9), (taxYear + 1, 1)]
        return parts.compactMap { calendar.date(from: DateComponents(year: $0.0, month: $0.1, day: 15)) }
            .map { nextBusinessDay(onOrAfter: $0, calendar: calendar) }
    }

    /// The deadlines that apply to one client for one tax year.
    static func deadlines(
        for entity: EntityType,
        taxYear: Int,
        extended: Bool,
        includeEstimates: Bool = true,
        calendar: Calendar = .current
    ) -> [Deadline] {
        guard let form = form(for: entity) else { return [] }
        var result: [Deadline] = []

        if includeEstimates && form == .f1040 {
            let names = ["Q1", "Q2", "Q3", "Q4"]
            for (index, date) in estimatedPaymentDates(taxYear: taxYear, calendar: calendar).enumerated() {
                result.append(Deadline(title: "\(taxYear) estimated tax \(names[index]) due", date: date, kind: .estimatedPayment, taxYear: taxYear))
            }
        }

        result.append(Deadline(
            title: "\(form.label) (\(taxYear)) due",
            date: dueDate(form: form, taxYear: taxYear, extended: false, calendar: calendar),
            kind: .filing, taxYear: taxYear
        ))
        if extended {
            result.append(Deadline(
                title: "\(form.label) (\(taxYear)) extended due",
                date: dueDate(form: form, taxYear: taxYear, extended: true, calendar: calendar),
                kind: .extended, taxYear: taxYear
            ))
        }
        return result.sorted { $0.date < $1.date }
    }

    // MARK: Business days

    static func nextBusinessDay(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<10 {
            let weekday = calendar.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 || isHoliday(day, calendar: calendar) {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            } else {
                return day
            }
        }
        return day
    }

    static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = c.year, let month = c.month, let day = c.day, let weekday = c.weekday else { return false }

        // Martin Luther King Jr. Day: third Monday of January.
        if month == 1 && weekday == 2 && (15...21).contains(day) { return true }

        // D.C. Emancipation Day (April 16); observed Friday if it falls on Saturday,
        // Monday if on Sunday. It moves the April filing deadline.
        if month == 4 {
            guard let april16 = calendar.date(from: DateComponents(year: year, month: 4, day: 16)) else { return false }
            let w = calendar.component(.weekday, from: april16)
            let observedDay = w == 7 ? 15 : (w == 1 ? 17 : 16)
            return day == observedDay
        }
        return false
    }
}
