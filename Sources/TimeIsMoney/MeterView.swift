import AppKit
import SwiftUI

/// e.g. 50038 -> "₩5만38원" (not "₩5.0만원") — exact 만/원 breakdown, no decimals.
func formatWon(_ value: Double) -> String {
    "₩" + formatWonBroken(Int(value.rounded()))
}

private func digitsOnly(_ s: String) -> String {
    s.filter(\.isNumber)
}

private enum CalendarCell: Hashable {
    case blank(Int)
    case day(Int)
}

private func formatClock(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "M/d HH:mm"
    return f.string(from: date)
}

/// Compact amount for a calendar day cell (no ₩ symbol, no decimals under 만).
private func calendarAmountText(_ value: Double) -> String {
    guard value > 0 else { return "" }
    if value < 10000 {
        return String(Int(value))
    }
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 1
    formatter.minimumFractionDigits = 0
    let man = value / 10000
    return (formatter.string(from: NSNumber(value: man)) ?? "0") + "만"
}

/// Breaks a won amount into 억/만/원 chunks for readability, e.g. 10090 -> "1만90원",
/// 60000000 -> "6000만원". Backs both the salary-input preview and formatWon.
func formatWonBroken(_ value: Int) -> String {
    guard value > 0 else { return "0원" }
    let eok = value / 100_000_000
    let afterEok = value % 100_000_000
    let man = afterEok / 10_000
    let rest = afterEok % 10_000

    var parts: [String] = []
    if eok > 0 { parts.append("\(eok)억") }
    if man > 0 { parts.append("\(man)만") }
    if rest > 0 || parts.isEmpty {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        parts.append(formatter.string(from: NSNumber(value: rest)) ?? "\(rest)")
    }
    return parts.joined() + "원"
}

struct MeterView: View {
    @ObservedObject var model: PayModel
    @State private var draftType: SalaryType
    @State private var draftAmountText: String
    @State private var draftPaydayText: String
    @State private var draftIsLastDay: Bool
    @State private var draftItemName: String
    @State private var draftItemPriceText: String
    @State private var calendarMonthOffset: Int = 0
    @State private var selectedCalendarDate: Date?

    init(model: PayModel) {
        self.model = model
        _draftType = State(initialValue: model.salaryType)
        _draftAmountText = State(initialValue: model.salaryAmount > 0 ? String(Int(model.salaryAmount)) : "")
        _draftIsLastDay = State(initialValue: model.paydayDay == 31)
        _draftPaydayText = State(initialValue: String(model.paydayDay))
        _draftItemName = State(initialValue: model.itemName)
        _draftItemPriceText = State(initialValue: String(Int(model.itemPrice)))
    }

    private var meterColor: Color { model.isRunning ? .green : .white }

    // 31 is the "말일" sentinel (always clamped to each month's actual last day),
    // so labeling it literally as "31일" would be wrong for any 28/29/30-day month.
    private var cumulativeResetLabel: String {
        model.paydayDay == 31 ? "누적 (매월 마지막 날 초기화)" : "누적 (매월 \(model.paydayDay)일 초기화)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showCalendar {
                calendarView
            } else if model.isRunning && !model.showDetail {
                compactView
            } else {
                detailView
            }
            Spacer(minLength: 0)
        }
        .frame(width: 220, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("오늘").font(.caption2).foregroundStyle(.gray)
            Text(formatWon(model.todayAmount))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(meterColor)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.88)))
        .shadow(radius: 8)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let update = model.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.url)
                } label: {
                    Text("🔔 새 버전 v\(update.version) — 눌러서 업데이트")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("오늘").font(.caption2).foregroundStyle(.gray)
                Text(formatWon(model.todayAmount))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(meterColor)
                if let start = model.lastStartDate {
                    Text("시작 \(formatClock(start))").font(.caption2).foregroundStyle(.gray)
                }
                if !model.isRunning, let stop = model.lastStopDate {
                    Text("종료 \(formatClock(stop))").font(.caption2).foregroundStyle(.gray)
                }
                if model.itemPrice > 0 {
                    Text("이 돈이면 \(model.itemName) \(Int(model.todayAmount / model.itemPrice))개!")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cumulativeResetLabel).font(.caption2).foregroundStyle(.gray)
                Text(formatWon(model.cumulativeAmount))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(meterColor.opacity(0.85))
            }

            Button(model.isRunning ? "근무 종료" : "근무 시작") {
                if model.isRunning {
                    model.stop()
                } else {
                    model.start()
                    model.showDetail = false
                }
            }
            .frame(maxWidth: .infinity)

            Divider().background(Color.gray)

            Picker("", selection: $draftType) {
                Text("월급").tag(SalaryType.monthly)
                Text("연봉").tag(SalaryType.annual)
                Text("시급").tag(SalaryType.hourly)
            }
            .pickerStyle(.segmented)

            TextField("금액 (원)", text: $draftAmountText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draftAmountText) { newValue in
                    let filtered = digitsOnly(newValue)
                    if filtered != newValue { draftAmountText = filtered }
                }
            if let amount = Int(draftAmountText), amount > 0 {
                Text(formatWonBroken(amount)).font(.caption2).foregroundStyle(.gray)
            }

            HStack {
                Text("급여일").foregroundStyle(.gray)
                TextField("1-31", text: $draftPaydayText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(draftIsLastDay)
                    .onChange(of: draftPaydayText) { newValue in
                        let filtered = digitsOnly(newValue)
                        if filtered != newValue { draftPaydayText = filtered }
                    }
                Text("일")
            }

            Toggle("말일 (매월 마지막 날)", isOn: $draftIsLastDay)
                .toggleStyle(.checkbox)
                .onChange(of: draftIsLastDay) { isLastDay in
                    if isLastDay { draftPaydayText = "31" }
                }

            Divider().background(Color.gray)

            TextField("비교 품목 (예: 피자헛 수퍼슈림프 L)", text: $draftItemName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("개당").foregroundStyle(.gray)
                TextField("가격", text: $draftItemPriceText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftItemPriceText) { newValue in
                        let filtered = digitsOnly(newValue)
                        if filtered != newValue { draftItemPriceText = filtered }
                    }
                Text("원")
            }

            Button("저장") {
                let amount = Double(draftAmountText) ?? 0
                let payday = draftIsLastDay ? 31 : (Int(draftPaydayText) ?? model.paydayDay)
                let price = Double(draftItemPriceText) ?? model.itemPrice
                model.applySettings(type: draftType, amount: amount, payday: payday, itemName: draftItemName, itemPrice: price)
            }
            .frame(maxWidth: .infinity)

            Button("캘린더") {
                calendarMonthOffset = 0
                selectedCalendarDate = nil
                model.showCalendar = true
            }
            .frame(maxWidth: .infinity)

            Button("종료") { NSApplication.shared.terminate(nil) }
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.88)))
        .shadow(radius: 8)
        .foregroundStyle(.white)
    }

    private var displayedMonth: Date {
        Calendar.current.date(byAdding: .month, value: calendarMonthOffset, to: Date()) ?? Date()
    }

    private var calendarView: some View {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) ?? DateInterval(start: displayedMonth, duration: 0)
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) // 1 = Sun
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let leadingBlanks = firstWeekday - 1
        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = "yyyy년 M월"
            return f
        }()
        let selectedDayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = "M월 d일 (E)"
            return f
        }()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("◀") { calendarMonthOffset -= 1 }
                    .disabled(calendarMonthOffset <= -(PayCalculator.historyRetentionDays / 30 - 1))
                Spacer()
                Text(monthFormatter.string(from: displayedMonth)).font(.caption).bold()
                Spacer()
                Button("▶") { calendarMonthOffset += 1 }
                    .disabled(calendarMonthOffset >= 0)
            }
            .onChange(of: calendarMonthOffset) { _ in selectedCalendarDate = nil }

            // A single ForEach over one unified, uniquely-identified array — LazyVGrid can
            // miscount/misplace items when leading blanks and days come from two separate
            // ForEach loops with overlapping `id: \.self` Int values (day 1 was vanishing).
            let cells: [CalendarCell] = (0..<leadingBlanks).map { .blank($0) } + (1...daysInMonth).map { .day($0) }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { w in
                    Text(w).font(.system(size: 9)).foregroundStyle(.gray)
                }
                ForEach(cells, id: \.self) { cell in
                    switch cell {
                    case .blank:
                        Color.clear.frame(height: 28)
                    case .day(let day):
                        let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) ?? monthInterval.start
                        let key = PayCalculator.dayKey(for: date)
                        let amount = model.dailyHistory[key] ?? 0
                        let isToday = calendar.isDateInToday(date)
                        let isSelected = selectedCalendarDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                        Button {
                            selectedCalendarDate = date
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(day)").font(.system(size: 10))
                                Text(calendarAmountText(amount))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Color.white.opacity(0.15) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selected = selectedCalendarDate {
                let key = PayCalculator.dayKey(for: selected)
                let amount = model.dailyHistory[key] ?? 0
                Divider().background(Color.gray)
                HStack {
                    Text(selectedDayFormatter.string(from: selected)).font(.caption).foregroundStyle(.gray)
                    Spacer()
                    Text(formatWon(amount)).font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }

            Button("상세로") {
                model.showCalendar = false
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.88)))
        .shadow(radius: 8)
        .foregroundStyle(.white)
    }
}
