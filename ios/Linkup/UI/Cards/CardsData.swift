import SwiftUI
import Charts
import UIKit

// MARK: - Shared Data Helpers & Palette

/// Standard palette for rich data visualizations.
/// Order: Claude orange accent, #7FB0F5 (blue), #6FB37E (green), #E8B04B (amber), #B48CF2 (purple).
private let dataPalette: [Color] = [
    Theme.accent,
    Color(red: 0x7F / 255.0, green: 0xB0 / 255.0, blue: 0xF5 / 255.0),
    Color(red: 0x6F / 255.0, green: 0xB3 / 255.0, blue: 0x7E / 255.0),
    Color(red: 0xE8 / 255.0, green: 0xB0 / 255.0, blue: 0x4B / 255.0),
    Color(red: 0xB4 / 255.0, green: 0x8C / 255.0, blue: 0xF2 / 255.0)
]

private func dataFormatNumber(_ num: Double) -> String {
    let absNum = abs(num)
    if absNum >= 1_000_000_000 {
        return String(format: "%.1fB", num / 1_000_000_000)
    } else if absNum >= 1_000_000 {
        return String(format: "%.1fM", num / 1_000_000)
    } else if absNum >= 1_000 {
        return String(format: "%.1fK", num / 1_000)
    } else if num.rounded() == num {
        return String(Int(num))
    } else {
        return String(format: "%.2f", num)
    }
}

private func dataFormatCurrency(_ val: Double, currency: String?) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = val >= 100 ? 2 : (val >= 1 ? 2 : 4)
    formatter.maximumFractionDigits = val >= 100 ? 2 : 4
    let formatted = formatter.string(from: NSNumber(value: val)) ?? String(val)
    let curr = currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "$"
    if curr == "$" || curr == "€" || curr == "£" || curr == "¥" {
        return "\(curr)\(formatted)"
    } else if !curr.isEmpty {
        return "\(formatted) \(curr)"
    }
    return formatted
}

private let dataISODateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let dataISODateOnlyFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f
}()

private let dataSimpleDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private func dataParseDate(_ string: String) -> Date? {
    if let d = dataISODateFormatter.date(from: string) { return d }
    if let d = dataISODateOnlyFormatter.date(from: string) { return d }
    if let d = dataSimpleDateFormatter.date(from: string) { return d }
    return nil
}

private let dataDisplayDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

private let dataDisplayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm"
    return f
}()

// MARK: - 1. ChartCard

private struct DataChartPoint: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let date: Date?
    let y: Double
}

private struct DataChartSeries: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let points: [DataChartPoint]
}

struct ChartCard: View {
    let card: JSONValue

    var body: some View {
        let title = card["title"]?.string
        let kind = card["kind"]?.string?.lowercased() ?? "line"
        let unit = card["unit"]?.string

        let seriesList = parseSeries()
        let isDateBased = checkIsDateBased(seriesList)

        CardContainer(title: "Chart", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {
                if kind == "pie" || kind == "donut" {
                    DataPieChartView(title: title, unit: unit, seriesList: seriesList, isDonut: kind == "donut")
                } else if isDateBased {
                    DataDateChartView(title: title, kind: kind, unit: unit, seriesList: seriesList)
                } else {
                    DataCategoryChartView(title: title, kind: kind, unit: unit, seriesList: seriesList)
                }
            }
        }
    }

    private func parseSeries() -> [DataChartSeries] {
        let rawSeries = card.objects("series")
        if !rawSeries.isEmpty {
            return rawSeries.map { s in
                let name = s["name"]?.string ?? ""
                let rawPoints = s.objects("points")
                let points: [DataChartPoint] = rawPoints.compactMap { pt in
                    let xStr = pt["x"]?.string ?? (pt["x"]?.double != nil ? String(Int(pt["x"]!.double!)) : "")
                    guard let yVal = pt["y"]?.double ?? (Double(pt["y"]?.string ?? "") ?? nil) else { return nil }
                    let d = dataParseDate(xStr)
                    return DataChartPoint(label: xStr, date: d, y: yVal)
                }
                return DataChartSeries(name: name, points: points)
            }
        }

        // Single series fallback at top-level
        let rawPoints = card.objects("points")
        if !rawPoints.isEmpty {
            let points: [DataChartPoint] = rawPoints.compactMap { pt in
                let xStr = pt["x"]?.string ?? (pt["x"]?.double != nil ? String(Int(pt["x"]!.double!)) : "")
                guard let yVal = pt["y"]?.double ?? (Double(pt["y"]?.string ?? "") ?? nil) else { return nil }
                let d = dataParseDate(xStr)
                return DataChartPoint(label: xStr, date: d, y: yVal)
            }
            return [DataChartSeries(name: card["title"]?.string ?? "", points: points)]
        }

        return []
    }

    private func checkIsDateBased(_ list: [DataChartSeries]) -> Bool {
        let allPoints = list.flatMap(\.points)
        guard !allPoints.isEmpty else { return false }
        return allPoints.allSatisfy { $0.date != nil }
    }
}

private struct DataDateChartView: View {
    let title: String?
    let kind: String
    let unit: String?
    let seriesList: [DataChartSeries]

    @State private var selectedDate: Date? = nil

    private var closestMatch: (seriesName: String, point: DataChartPoint)? {
        guard let sel = selectedDate else { return nil }
        var best: (String, DataChartPoint)?
        var minDiff: TimeInterval = .infinity
        for s in seriesList {
            for pt in s.points {
                if let d = pt.date {
                    let diff = abs(d.timeIntervalSince(sel))
                    if diff < minDiff {
                        minDiff = diff
                        best = (s.name, pt)
                    }
                }
            }
        }
        return best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header readout
            HStack(alignment: .firstTextBaseline) {
                if let match = closestMatch {
                    VStack(alignment: .leading, spacing: 2) {
                        if let d = match.point.date {
                            Text(dataDisplayDateFormatter.string(from: d))
                                .font(Theme.sans(11, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        HStack(spacing: 4) {
                            Text(dataFormatNumber(match.point.y))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .contentTransition(.numericText())
                            if let unit, !unit.isEmpty {
                                Text(unit)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    Spacer()
                    if !match.seriesName.isEmpty {
                        Text(match.seriesName)
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    Button {
                        withAnimation(.snappy) { selectedDate = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                } else {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(Theme.sans(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.elevated, in: Capsule())
                    }
                }
            }

            if seriesList.isEmpty || seriesList.allSatisfy({ $0.points.isEmpty }) {
                Text("No data points")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 120)
            } else {
                Chart {
                    ForEach(Array(seriesList.enumerated()), id: \.element.id) { sIndex, series in
                        let color = dataPalette[sIndex % dataPalette.count]
                        ForEach(series.points) { pt in
                            if let date = pt.date {
                                switch kind {
                                case "bar":
                                    BarMark(
                                        x: .value("Date", date),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                case "area":
                                    AreaMark(
                                        x: .value("Date", date),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [color.opacity(0.35), color.opacity(0.02)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    LineMark(
                                        x: .value("Date", date),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                default:
                                    LineMark(
                                        x: .value("Date", date),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    PointMark(
                                        x: .value("Date", date),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                    .symbolSize(series.points.count < 14 ? 20 : 0)
                                }
                            }
                        }
                    }

                    if let selectedDate {
                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(Theme.secondaryText.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let num = value.as(Double.self) {
                                Text(dataFormatNumber(num))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel()
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(height: 180)
            }

            // Legend
            if seriesList.count > 1 || (seriesList.first?.name.isEmpty == false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(seriesList.enumerated()), id: \.element.id) { sIndex, s in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(dataPalette[sIndex % dataPalette.count])
                                    .frame(width: 8, height: 8)
                                Text(s.name.isEmpty ? "Series \(sIndex + 1)" : s.name)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct DataCategoryChartView: View {
    let title: String?
    let kind: String
    let unit: String?
    let seriesList: [DataChartSeries]

    @State private var selectedCategory: String? = nil

    private var closestMatch: (seriesName: String, point: DataChartPoint)? {
        guard let sel = selectedCategory else { return nil }
        for s in seriesList {
            if let pt = s.points.first(where: { $0.label == sel }) {
                return (s.name, pt)
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header readout
            HStack(alignment: .firstTextBaseline) {
                if let match = closestMatch {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.point.label)
                            .font(Theme.sans(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        HStack(spacing: 4) {
                            Text(dataFormatNumber(match.point.y))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .contentTransition(.numericText())
                            if let unit, !unit.isEmpty {
                                Text(unit)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    Spacer()
                    if !match.seriesName.isEmpty {
                        Text(match.seriesName)
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    Button {
                        withAnimation(.snappy) { selectedCategory = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                } else {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(Theme.sans(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.elevated, in: Capsule())
                    }
                }
            }

            if seriesList.isEmpty || seriesList.allSatisfy({ $0.points.isEmpty }) {
                Text("No data points")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 120)
            } else {
                Chart {
                    ForEach(Array(seriesList.enumerated()), id: \.element.id) { sIndex, series in
                        let color = dataPalette[sIndex % dataPalette.count]
                        ForEach(series.points) { pt in
                            switch kind {
                            case "bar":
                                if seriesList.count > 1 {
                                    BarMark(
                                        x: .value("Category", pt.label),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                    .position(by: .value("Series", series.name.isEmpty ? "\(sIndex)" : series.name))
                                } else {
                                    BarMark(
                                        x: .value("Category", pt.label),
                                        y: .value("Value", pt.y)
                                    )
                                    .foregroundStyle(color)
                                }
                            case "area":
                                AreaMark(
                                    x: .value("Category", pt.label),
                                    y: .value("Value", pt.y)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [color.opacity(0.35), color.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                LineMark(
                                    x: .value("Category", pt.label),
                                    y: .value("Value", pt.y)
                                )
                                .foregroundStyle(color)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            default:
                                LineMark(
                                    x: .value("Category", pt.label),
                                    y: .value("Value", pt.y)
                                )
                                .foregroundStyle(color)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                PointMark(
                                    x: .value("Category", pt.label),
                                    y: .value("Value", pt.y)
                                )
                                .foregroundStyle(color)
                                .symbolSize(series.points.count < 14 ? 20 : 0)
                            }
                        }
                    }

                    if let selectedCategory {
                        RuleMark(x: .value("Selected", selectedCategory))
                            .foregroundStyle(Theme.secondaryText.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXSelection(value: $selectedCategory)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let num = value.as(Double.self) {
                                Text(dataFormatNumber(num))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel()
                            .font(Theme.sans(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(height: 180)
            }

            // Legend
            if seriesList.count > 1 || (seriesList.first?.name.isEmpty == false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(seriesList.enumerated()), id: \.element.id) { sIndex, s in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(dataPalette[sIndex % dataPalette.count])
                                    .frame(width: 8, height: 8)
                                Text(s.name.isEmpty ? "Series \(sIndex + 1)" : s.name)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct DataPieSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

private struct DataPieChartView: View {
    let title: String?
    let unit: String?
    let seriesList: [DataChartSeries]
    let isDonut: Bool

    @State private var selectedSliceIndex: Int? = nil

    private var slices: [DataPieSlice] {
        if seriesList.count == 1, let first = seriesList.first {
            return first.points.enumerated().map { idx, pt in
                DataPieSlice(
                    label: pt.label.isEmpty ? "Item \(idx + 1)" : pt.label,
                    value: pt.y,
                    color: dataPalette[idx % dataPalette.count]
                )
            }
        }
        return seriesList.enumerated().map { idx, s in
            let total = s.points.map(\.y).reduce(0, +)
            return DataPieSlice(
                label: s.name.isEmpty ? "Series \(idx + 1)" : s.name,
                value: total,
                color: dataPalette[idx % dataPalette.count]
            )
        }
    }

    private var totalValue: Double {
        slices.map(\.value).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            if slices.isEmpty {
                Text("No data points")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 120)
            } else {
                ZStack {
                    Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        SectorMark(
                            angle: .value("Value", slice.value),
                            innerRadius: .ratio(isDonut ? 0.62 : 0),
                            angularInset: 1.5
                        )
                        .foregroundStyle(slice.color)
                        .opacity(selectedSliceIndex == nil || selectedSliceIndex == index ? 1.0 : 0.35)
                    }
                    .frame(height: 180)

                    if isDonut {
                        VStack(spacing: 2) {
                            if let sel = selectedSliceIndex, sel < slices.count {
                                Text(slices[sel].label)
                                    .font(Theme.sans(11, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                                Text(dataFormatNumber(slices[sel].value))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                    .contentTransition(.numericText())
                            } else {
                                Text("TOTAL")
                                    .font(Theme.sans(10, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                Text(dataFormatNumber(totalValue))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            if let unit, !unit.isEmpty {
                                Text(unit)
                                    .font(Theme.sans(10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: 100)
                    }
                }

                // Tappable Legend
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(slices.enumerated()), id: \.element.id) { idx, slice in
                            Button {
                                withAnimation(.snappy) {
                                    if selectedSliceIndex == idx {
                                        selectedSliceIndex = nil
                                    } else {
                                        selectedSliceIndex = idx
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(slice.color)
                                        .frame(width: 8, height: 8)
                                    Text(slice.label)
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.text)
                                    Text(dataFormatNumber(slice.value))
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selectedSliceIndex == idx ? slice.color.opacity(0.18) : Theme.elevated,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(selectedSliceIndex == idx ? slice.color : Theme.hairline)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - 2. StockCard & 3. CryptoCard Shared Infrastructure

private struct DataSparkPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
    let label: String
}

private struct DataFinancialCardView: View {
    let cardType: String
    let symbol: String
    let name: String
    let price: Double?
    let priceString: String?
    let change: Double?
    let changePercent: Double?
    let currency: String?
    let points: [DataSparkPoint]
    let stats: [(label: String, value: String)]

    @State private var scrubbedIndex: Int? = nil

    private var isPositive: Bool {
        if let c = change { return c >= 0 }
        if let cp = changePercent { return cp >= 0 }
        return true
    }

    private var currentDisplayPrice: String {
        if let idx = scrubbedIndex, idx >= 0, idx < points.count {
            return dataFormatCurrency(points[idx].value, currency: currency)
        }
        if let price {
            return dataFormatCurrency(price, currency: currency)
        }
        if let priceString, !priceString.isEmpty {
            return priceString
        }
        return "—"
    }

    private var currentDisplaySubtitle: String? {
        if let idx = scrubbedIndex, idx >= 0, idx < points.count, !points[idx].label.isEmpty {
            return points[idx].label
        }
        return name.isEmpty ? nil : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row: Symbol + Name, Change Pill
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.isEmpty ? cardType : symbol)
                        .font(Theme.sans(18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if let subtitle = currentDisplaySubtitle {
                        Text(subtitle)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // Change Pill
                if change != nil || changePercent != nil {
                    HStack(spacing: 3) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        if let c = change {
                            let sign = c >= 0 ? "+" : ""
                            Text("\(sign)\(String(format: "%.2f", c))")
                                .font(Theme.mono(11))
                        }
                        if let cp = changePercent {
                            let sign = cp >= 0 ? "+" : ""
                            Text("(\(sign)\(String(format: "%.2f", cp))%)")
                                .font(Theme.mono(11))
                        }
                    }
                    .foregroundStyle(isPositive ? Theme.success : Theme.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isPositive ? Theme.success : Theme.danger).opacity(0.14), in: Capsule())
                }
            }

            // Big Price
            Text(currentDisplayPrice)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())

            // Sparkline / Area Chart
            if points.count >= 2 {
                let trendColor = isPositive ? Theme.success : Theme.danger
                let values = points.map(\.value)
                let minVal = values.min() ?? 0
                let maxVal = values.max() ?? 1
                let spread = max(maxVal - minVal, 0.0001)
                let yMin = minVal - spread * 0.08
                let yMax = maxVal + spread * 0.08

                Chart {
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Index", pt.index),
                            yStart: .value("Baseline", yMin),
                            yEnd: .value("Price", pt.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [trendColor.opacity(0.28), trendColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Index", pt.index),
                            y: .value("Price", pt.value)
                        )
                        .foregroundStyle(trendColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    if let scrubbedIndex {
                        RuleMark(x: .value("Selected", scrubbedIndex))
                            .foregroundStyle(Theme.secondaryText.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        if scrubbedIndex < points.count {
                            PointMark(
                                x: .value("Selected", scrubbedIndex),
                                y: .value("SelectedPrice", points[scrubbedIndex].value)
                            )
                            .foregroundStyle(trendColor)
                            .symbolSize(30)
                        }
                    }
                }
                .chartXSelection(value: $scrubbedIndex)
                .chartYScale(domain: yMin...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 90)
            }

            // Stats Row
            if !stats.isEmpty {
                HStack(spacing: 16) {
                    ForEach(stats, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.label)
                                .font(Theme.sans(11))
                                .foregroundStyle(Theme.secondaryText)
                            Text(stat.value)
                                .font(Theme.sans(13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - 2. StockCard

struct StockCard: View {
    let card: JSONValue

    var body: some View {
        let symbol = card["symbol"]?.string ?? ""
        let name = card["name"]?.string ?? ""
        let price = card["price"]?.double ?? (Double(card["price"]?.string ?? "") ?? nil)
        let priceString = card["price"]?.string
        let change = card["change"]?.double ?? (Double(card["change"]?.string ?? "") ?? nil)
        let changePercent = card["changePercent"]?.double ?? (Double(card["changePercent"]?.string ?? "") ?? nil)
        let currency = card["currency"]?.string ?? "$"
        let marketCap = card["marketCap"]?.string ?? (card["marketCap"]?.double != nil ? dataFormatNumber(card["marketCap"]!.double!) : nil)
        let exchange = card["exchange"]?.string

        let rawPoints = card.objects("points")
        let points: [DataSparkPoint] = rawPoints.enumerated().compactMap { idx, pt in
            guard let yVal = pt["y"]?.double ?? (Double(pt["y"]?.string ?? "") ?? nil) else { return nil }
            let xLabel = pt["x"]?.string ?? ""
            return DataSparkPoint(index: idx, value: yVal, label: xLabel)
        }

        let stats: [(label: String, value: String)] = [
            ("Exchange", exchange), ("Market Cap", marketCap), ("Currency", card["currency"]?.string)
        ].compactMap { pair in pair.1.flatMap { $0.isEmpty ? nil : (label: pair.0, value: $0) } }

        CardContainer(title: "Stock", symbol: "chart.line.uptrend.xyaxis") {
            DataFinancialCardView(
                cardType: "Stock",
                symbol: symbol,
                name: name,
                price: price,
                priceString: priceString,
                change: change,
                changePercent: changePercent,
                currency: currency,
                points: points,
                stats: stats
            )
        }
    }
}

// MARK: - 3. CryptoCard

struct CryptoCard: View {
    let card: JSONValue

    var body: some View {
        let symbol = card["symbol"]?.string ?? ""
        let name = card["name"]?.string ?? ""
        let price = card["price"]?.double ?? (Double(card["price"]?.string ?? "") ?? nil)
        let priceString = card["price"]?.string
        let change = card["change24h"]?.double ?? (Double(card["change24h"]?.string ?? "") ?? nil)
        let changePercent = card["changePercent24h"]?.double ?? (Double(card["changePercent24h"]?.string ?? "") ?? nil)
        let currency = card["currency"]?.string ?? "$"

        let rawPoints = card.objects("points")
        let points: [DataSparkPoint] = rawPoints.enumerated().compactMap { idx, pt in
            guard let yVal = pt["y"]?.double ?? (Double(pt["y"]?.string ?? "") ?? nil) else { return nil }
            let xLabel = pt["x"]?.string ?? ""
            return DataSparkPoint(index: idx, value: yVal, label: xLabel)
        }

        let stats: [(label: String, value: String)] = [
            ("Currency", card["currency"]?.string), ("Market Cap", card["marketCap"]?.string)
        ].compactMap { pair in pair.1.flatMap { $0.isEmpty ? nil : (label: pair.0, value: $0) } }

        CardContainer(title: "Crypto", symbol: "bitcoinsign.circle") {
            DataFinancialCardView(
                cardType: "Crypto",
                symbol: symbol,
                name: name,
                price: price,
                priceString: priceString,
                change: change,
                changePercent: changePercent,
                currency: currency,
                points: points,
                stats: stats
            )
        }
    }
}

// MARK: - 4. MetricsCard

private struct DataMetricItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let delta: String?
    let trend: String? // "up" | "down" | "flat"
}

struct MetricsCard: View {
    let card: JSONValue

    private var items: [DataMetricItem] {
        card.objects("items").map { item in
            let label = item["label"]?.string ?? ""
            let value = item["value"]?.string ?? (item["value"]?.double != nil ? dataFormatNumber(item["value"]!.double!) : "")
            let delta = item["delta"]?.string ?? (item["delta"]?.double != nil ? String(format: "%.1f", item["delta"]!.double!) : nil)
            let trend = item["trend"]?.string?.lowercased()
            return DataMetricItem(label: label, value: value, delta: delta, trend: trend)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        let title = card["title"]?.string

        CardContainer(title: "Metrics", symbol: "gauge.with.dots.needle.bottom.50percent") {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if items.isEmpty {
                    Text("No metrics data")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.label)
                                    .font(Theme.sans(12, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)

                                Text(item.value)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                    .contentTransition(.numericText())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                if let delta = item.delta, !delta.isEmpty {
                                    let trend = item.trend ?? (delta.hasPrefix("+") ? "up" : (delta.hasPrefix("-") ? "down" : "flat"))
                                    HStack(spacing: 3) {
                                        if trend == "up" {
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.success)
                                            Text(delta)
                                                .font(Theme.sans(11, weight: .semibold))
                                                .foregroundStyle(Theme.success)
                                        } else if trend == "down" {
                                            Image(systemName: "arrow.down.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.danger)
                                            Text(delta)
                                                .font(Theme.sans(11, weight: .semibold))
                                                .foregroundStyle(Theme.danger)
                                        } else {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.secondaryText)
                                            Text(delta)
                                                .font(Theme.sans(11, weight: .semibold))
                                                .foregroundStyle(Theme.secondaryText)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 5. TableCard

struct TableCard: View {
    let card: JSONValue
    @State private var showCopiedNotification = false

    private var columns: [String] {
        card.strings("columns")
    }

    private var rows: [[String]] {
        let rawRows = card["rows"]?.array ?? []
        return rawRows.map { row in
            row.array?.compactMap { cell in
                cell.string ?? ""
            } ?? []
        }
    }

    private func isNumericString(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty else { return false }
        return Double(trimmed) != nil
    }

    private func isColumnNumeric(_ colIndex: Int) -> Bool {
        let nonEmpties = rows.compactMap { r -> String? in
            guard colIndex < r.count else { return nil }
            let c = r[colIndex]
            return c.isEmpty ? nil : c
        }
        guard !nonEmpties.isEmpty else { return false }
        let numericCount = nonEmpties.filter(isNumericString).count
        return Double(numericCount) / Double(nonEmpties.count) >= 0.7
    }

    private func copyAsCSV() {
        func escapeCSV(_ str: String) -> String {
            if str.contains(",") || str.contains("\"") || str.contains("\n") {
                let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return str
        }
        var lines: [String] = []
        if !columns.isEmpty {
            lines.append(columns.map(escapeCSV).joined(separator: ","))
        }
        for row in rows {
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            showCopiedNotification = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.snappy) {
                showCopiedNotification = false
            }
        }
    }

    var body: some View {
        let title = card["title"]?.string

        CardContainer(title: "Table", symbol: "tablecells") {
            VStack(alignment: .leading, spacing: 10) {
                // Header with title and menu
                HStack {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    if showCopiedNotification {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Copied CSV")
                                .font(Theme.sans(11, weight: .medium))
                        }
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.success.opacity(0.12), in: Capsule())
                    }
                    Menu {
                        Button {
                            copyAsCSV()
                        } label: {
                            Label("Copy as CSV", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(4)
                    }
                }

                if columns.isEmpty && rows.isEmpty {
                    Text("Empty table")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 2) {
                            if !columns.isEmpty {
                                GridRow {
                                    ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, col in
                                        Text(col)
                                            .font(Theme.sans(11, weight: .semibold))
                                            .foregroundStyle(Theme.secondaryText)
                                            .textCase(.uppercase)
                                            .frame(maxWidth: .infinity, alignment: isColumnNumeric(colIdx) ? .trailing : .leading)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 8)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                }
                            }

                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                                GridRow {
                                    ForEach(0..<columns.count, id: \.self) { colIdx in
                                        let cell = colIdx < row.count ? row[colIdx] : ""
                                        let isNum = isColumnNumeric(colIdx) || isNumericString(cell)
                                        Text(cell)
                                            .font(isNum ? Theme.mono(12) : Theme.sans(13))
                                            .foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: isNum ? .trailing : .leading)
                                            .padding(.vertical, 7)
                                            .padding(.horizontal, 8)
                                    }
                                }
                                .background(
                                    rowIdx % 2 == 1 ? Theme.elevated.opacity(0.4) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// MARK: - 6. ComparisonCard

private struct DataComparisonItem: Identifiable {
    let id = UUID()
    let name: String
    let imageURL: URL?
    let price: String?
    let rating: Double?
    let pros: [String]
    let cons: [String]
    let highlights: [String: String]
}

struct ComparisonCard: View {
    let card: JSONValue

    private var items: [DataComparisonItem] {
        card.objects("items").map { it in
            let name = it["name"]?.string ?? ""
            let img = it["image"]?.string.flatMap(URL.init)
            let price = it["price"]?.string ?? (it["price"]?.double != nil ? dataFormatCurrency(it["price"]!.double!, currency: "$") : nil)
            let rating = it["rating"]?.double ?? (Double(it["rating"]?.string ?? "") ?? nil)
            let pros = it.strings("pros")
            let cons = it.strings("cons")
            var highlights: [String: String] = [:]
            if let obj = it["highlights"]?.object {
                for (k, v) in obj {
                    highlights[k] = v.string ?? ""
                }
            }
            return DataComparisonItem(name: name, imageURL: img, price: price, rating: rating, pros: pros, cons: cons, highlights: highlights)
        }
    }

    private var allHighlightLabels: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for it in items {
            for (k, _) in it.highlights {
                if seen.insert(k).inserted {
                    list.append(k)
                }
            }
        }
        return list
    }

    var body: some View {
        let title = card["title"]?.string
        let highlightLabels = allHighlightLabels

        CardContainer(title: "Comparison", symbol: "arrow.left.and.right") {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if items.isEmpty {
                    Text("No items to compare")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    // Image
                                    if let url = item.imageURL {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 110)
                                                    .clipped()
                                            case .empty:
                                                ZStack {
                                                    Theme.elevated
                                                    ProgressView().tint(Theme.secondaryText)
                                                }
                                                .frame(height: 110)
                                            case .failure:
                                                ZStack {
                                                    Theme.elevated
                                                    Image(systemName: "photo")
                                                        .font(.system(size: 24))
                                                        .foregroundStyle(Theme.tertiaryText)
                                                }
                                                .frame(height: 110)
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }

                                    // Name & Price & Rating
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(Theme.sans(14, weight: .bold))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(2)
                                            .frame(minHeight: 36, alignment: .topLeading)

                                        HStack(alignment: .firstTextBaseline) {
                                            if let p = item.price, !p.isEmpty {
                                                Text(p)
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(Theme.accent)
                                            }
                                            Spacer()
                                            if let r = item.rating {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "star.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.yellow)
                                                    Text(String(format: "%.1f", r))
                                                        .font(Theme.sans(11, weight: .semibold))
                                                        .foregroundStyle(Theme.text)
                                                }
                                            }
                                        }
                                    }

                                    // Highlights aligned rows
                                    if !highlightLabels.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                            Text("HIGHLIGHTS")
                                                .font(Theme.sans(10, weight: .bold))
                                                .foregroundStyle(Theme.secondaryText)

                                            ForEach(highlightLabels, id: \.self) { label in
                                                HStack {
                                                    Text(label)
                                                        .font(Theme.sans(11))
                                                        .foregroundStyle(Theme.secondaryText)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Text(item.highlights[label] ?? "—")
                                                        .font(Theme.sans(11, weight: .medium))
                                                        .foregroundStyle(item.highlights[label] != nil ? Theme.text : Theme.tertiaryText)
                                                        .lineLimit(1)
                                                }
                                                .frame(height: 18)
                                            }
                                        }
                                    }

                                    // Pros
                                    if !item.pros.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                            Text("PROS")
                                                .font(Theme.sans(10, weight: .bold))
                                                .foregroundStyle(Theme.secondaryText)
                                            ForEach(item.pros, id: \.self) { pro in
                                                HStack(alignment: .top, spacing: 4) {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(Theme.success)
                                                        .padding(.top, 2)
                                                    Text(pro)
                                                        .font(Theme.sans(12))
                                                        .foregroundStyle(Theme.text)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }

                                    // Cons
                                    if !item.cons.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                            Text("CONS")
                                                .font(Theme.sans(10, weight: .bold))
                                                .foregroundStyle(Theme.secondaryText)
                                            ForEach(item.cons, id: \.self) { con in
                                                HStack(alignment: .top, spacing: 4) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(Theme.danger)
                                                        .padding(.top, 2)
                                                    Text(con)
                                                        .font(Theme.sans(12))
                                                        .foregroundStyle(Theme.text)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(width: 220)
                                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 7. SportsCard

private struct DataTeamInitialsCircle: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Theme.elevated)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Theme.hairline))
            .overlay(
                Text(initials.isEmpty ? "?" : initials)
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.text)
            )
    }
}

private struct DataTeamLogoView: View {
    let name: String
    let logoURL: URL?

    var body: some View {
        if let logoURL {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                default:
                    DataTeamInitialsCircle(name: name)
                }
            }
        } else {
            DataTeamInitialsCircle(name: name)
        }
    }
}

private struct DataSportsStatusPill: View {
    let status: String
    @State private var isPulsing = false

    private var isLive: Bool {
        status.localizedCaseInsensitiveContains("live")
    }

    var body: some View {
        if !status.isEmpty {
            HStack(spacing: 5) {
                if isLive {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 1.0 : 0.25)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                }
                Text(status.uppercased())
                    .font(Theme.sans(10, weight: .bold))
                    .foregroundStyle(isLive ? Theme.danger : Theme.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isLive ? Theme.danger.opacity(0.15) : Theme.elevated, in: Capsule())
            .overlay(Capsule().stroke(isLive ? Theme.danger.opacity(0.3) : Theme.hairline))
        }
    }
}

struct SportsCard: View {
    let card: JSONValue

    var body: some View {
        let league = card["league"]?.string
        let status = card["status"]?.string ?? ""
        let events = card.strings("events")

        let home = card["home"]
        let homeName = home?["name"]?.string ?? "Home"
        let homeLogo = home?["logo"]?.string.flatMap(URL.init)
        let homeScore = home?["score"]?.string ?? (home?["score"]?.double != nil ? String(Int(home!["score"]!.double!)) : nil)

        let away = card["away"]
        let awayName = away?["name"]?.string ?? "Away"
        let awayLogo = away?["logo"]?.string.flatMap(URL.init)
        let awayScore = away?["score"]?.string ?? (away?["score"]?.double != nil ? String(Int(away!["score"]!.double!)) : nil)

        CardContainer(title: league ?? "Sports", symbol: "sportscourt") {
            VStack(alignment: .leading, spacing: 14) {
                // Scoreboard Row
                HStack(alignment: .center, spacing: 12) {
                    // Home
                    VStack(spacing: 6) {
                        DataTeamLogoView(name: homeName, logoURL: homeLogo)
                        Text(homeName)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)

                    // Center Score & Status
                    VStack(spacing: 6) {
                        DataSportsStatusPill(status: status)

                        if let h = homeScore, let a = awayScore {
                            HStack(spacing: 8) {
                                Text(h)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Text(":")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                                Text(a)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                        } else {
                            Text("vs")
                                .font(Theme.sans(18, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    // Away
                    VStack(spacing: 6) {
                        DataTeamLogoView(name: awayName, logoURL: awayLogo)
                        Text(awayName)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)

                // Events
                if !events.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Text("KEY EVENTS")
                            .font(Theme.sans(10, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)

                        ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
                            HStack(spacing: 8) {
                                Circle().fill(Theme.accent).frame(width: 4, height: 4)
                                Text(ev)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - 8. PollCard

struct PollCard: View {
    let card: JSONValue
    @State private var selectedOption: String? = nil
    @Environment(\.cardActions) private var cardActions

    private var question: String {
        card["question"]?.string ?? ""
    }

    private var options: [String] {
        card.strings("options")
    }

    var body: some View {
        CardContainer(title: "Poll", symbol: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 12) {
                if !question.isEmpty {
                    Text(question)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if options.isEmpty {
                    Text("No poll options")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    VStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            let isSelected = selectedOption == option

                            Button {
                                guard selectedOption == nil else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.snappy) {
                                    selectedOption = option
                                }
                                cardActions.send("I vote: \(option)")
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(Theme.sans(14, weight: .medium))
                                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.9))
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Theme.accent)
                                    } else {
                                        Image(systemName: "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Theme.tertiaryText)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    isSelected ? Theme.accent.opacity(0.12) : Theme.elevated,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? Theme.accent.opacity(0.4) : Theme.hairline)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedOption != nil)
                        }
                    }

                    if let selected = selectedOption {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.success)
                            Text("Vote submitted: \(selected)")
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
}

// MARK: - 9. ProgressCard

private struct DataProgressItem: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let note: String?
}

private struct DataProgressRing: View {
    let progress: Double
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.elevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(progress, 1.0))))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(max(0, min(progress, 1.0)) * 100))%")
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
    }
}

struct ProgressCard: View {
    let card: JSONValue

    private var items: [DataProgressItem] {
        let raw = card.objects("items")
        if !raw.isEmpty {
            return raw.map { it in
                let label = it["label"]?.string ?? ""
                let rawVal = it["value"]?.double ?? (Double(it["value"]?.string ?? "") ?? 0.0)
                let norm = rawVal > 1.0 ? rawVal / 100.0 : rawVal
                let note = it["note"]?.string
                return DataProgressItem(label: label, value: max(0.0, min(norm, 1.0)), note: note)
            }
        }

        // Single item fallback at top-level
        if let rawVal = card["value"]?.double ?? (Double(card["value"]?.string ?? "") ?? nil) {
            let label = card["label"]?.string ?? (card["title"]?.string ?? "Progress")
            let norm = rawVal > 1.0 ? rawVal / 100.0 : rawVal
            let note = card["note"]?.string
            return [DataProgressItem(label: label, value: max(0.0, min(norm, 1.0)), note: note)]
        }
        return []
    }

    var body: some View {
        let title = card["title"]?.string

        CardContainer(title: "Progress", symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if items.isEmpty {
                    Text("No progress items")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else if items.count == 1, let item = items.first {
                    // Single prominent progress with ring + bar
                    HStack(spacing: 16) {
                        DataProgressRing(progress: item.value)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.label)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if let note = item.note, !note.isEmpty {
                                Text(note)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            // Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Theme.elevated)
                                        .frame(height: 7)
                                    Capsule()
                                        .fill(Theme.accent)
                                        .frame(width: max(0, min(geo.size.width * CGFloat(item.value), geo.size.width)), height: 7)
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    // Multiple items with horizontal bars
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.label)
                                        .font(Theme.sans(13, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                    Spacer()
                                    if let note = item.note, !note.isEmpty {
                                        Text(note)
                                            .font(Theme.sans(12))
                                            .foregroundStyle(Theme.secondaryText)
                                    } else {
                                        Text("\(Int(item.value * 100))%")
                                            .font(Theme.mono(12))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Theme.elevated)
                                            .frame(height: 7)
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Theme.accent, Theme.accent.opacity(0.8)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(0, min(geo.size.width * CGFloat(item.value), geo.size.width)), height: 7)
                                    }
                                }
                                .frame(height: 7)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 10. TimelineCard

private struct DataTimelineItem: Identifiable {
    let id = UUID()
    let date: String?
    let title: String?
    let detail: String?
}

struct TimelineCard: View {
    let card: JSONValue

    private var items: [DataTimelineItem] {
        card.objects("items").map { it in
            let date = it["date"]?.string
            let title = it["title"]?.string
            let detail = it["detail"]?.string
            return DataTimelineItem(date: date, title: title, detail: detail)
        }
    }

    var body: some View {
        let title = card["title"]?.string

        CardContainer(title: "Timeline", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if items.isEmpty {
                    Text("No timeline events")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                // Dot & connecting line
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(index == 0 ? Theme.accent : Theme.secondaryText)
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Circle()
                                                .stroke(index == 0 ? Theme.accent.opacity(0.3) : Color.clear, lineWidth: 4)
                                        )
                                        .padding(.top, 3)

                                    if index < items.count - 1 {
                                        Rectangle()
                                            .fill(Theme.hairline)
                                            .frame(width: 2)
                                            .frame(minHeight: 34)
                                    }
                                }
                                .frame(width: 14)

                                // Content
                                VStack(alignment: .leading, spacing: 3) {
                                    if let date = item.date, !date.isEmpty {
                                        Text(date)
                                            .font(Theme.sans(11, weight: .semibold))
                                            .foregroundStyle(index == 0 ? Theme.accent : Theme.secondaryText)
                                            .textCase(.uppercase)
                                    }
                                    if let t = item.title, !t.isEmpty {
                                        Text(t)
                                            .font(Theme.sans(14, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                    }
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(Theme.sans(12))
                                            .foregroundStyle(Theme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.bottom, index < items.count - 1 ? 14 : 2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 11. ConversionCard

struct ConversionCard: View {
    let card: JSONValue

    var body: some View {
        let fromObj = card["from"]
        let fromValue = fromObj?["value"]?.string ?? (fromObj?["value"]?.double != nil ? dataFormatNumber(fromObj!["value"]!.double!) : "—")
        let fromUnit = fromObj?["unit"]?.string ?? ""

        let toObj = card["to"]
        let toValue = toObj?["value"]?.string ?? (toObj?["value"]?.double != nil ? dataFormatNumber(toObj!["value"]!.double!) : "—")
        let toUnit = toObj?["unit"]?.string ?? ""

        let formula = card["formula"]?.string

        CardContainer(title: "Conversion", symbol: "arrow.triangle.swap") {
            VStack(alignment: .leading, spacing: 12) {
                // Conversion Tiles
                HStack(alignment: .center, spacing: 10) {
                    // From
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fromValue)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !fromUnit.isEmpty {
                            Text(fromUnit)
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.accent)

                    // To
                    VStack(alignment: .leading, spacing: 4) {
                        Text(toValue)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !toUnit.isEmpty {
                            Text(toUnit)
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
                }

                // Formula row
                if let formula, !formula.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "function")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Text(formula)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}
