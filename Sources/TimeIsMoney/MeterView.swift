import AppKit
import SwiftUI

func formatWon(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    if value < 10000 {
        formatter.maximumFractionDigits = 0
        return "₩" + (formatter.string(from: NSNumber(value: value)) ?? "0")
    } else {
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let man = value / 10000
        return "₩" + (formatter.string(from: NSNumber(value: man)) ?? "0") + "만원"
    }
}

private func digitsOnly(_ s: String) -> String {
    s.filter(\.isNumber)
}

/// Breaks a large exact won amount into 억/만 chunks for readability while typing,
/// e.g. 10090 -> "1만90원", 60000000 -> "6000만원". Unlike formatWon this keeps the
/// exact figure (no rounding) since it's echoing back what the user just typed.
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

    init(model: PayModel) {
        self.model = model
        _draftType = State(initialValue: model.salaryType)
        _draftAmountText = State(initialValue: model.salaryAmount > 0 ? String(Int(model.salaryAmount)) : "")
        _draftIsLastDay = State(initialValue: model.paydayDay == 31)
        _draftPaydayText = State(initialValue: String(model.paydayDay))
    }

    private var meterColor: Color { model.isRunning ? .green : .white }

    // 31 is the "말일" sentinel (always clamped to each month's actual last day),
    // so labeling it literally as "31일" would be wrong for any 28/29/30-day month.
    private var cumulativeResetLabel: String {
        model.paydayDay == 31 ? "누적 (매월 마지막 날 초기화)" : "누적 (매월 \(model.paydayDay)일 초기화)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isRunning && !model.showDetail {
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
            VStack(alignment: .leading, spacing: 2) {
                Text("오늘").font(.caption2).foregroundStyle(.gray)
                Text(formatWon(model.todayAmount))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(meterColor)
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

            Button("저장") {
                let amount = Double(draftAmountText) ?? 0
                let payday = draftIsLastDay ? 31 : (Int(draftPaydayText) ?? model.paydayDay)
                model.applySettings(type: draftType, amount: amount, payday: payday)
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
}
