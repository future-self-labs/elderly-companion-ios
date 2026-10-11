import Charts
import SwiftUI

/// Mood (and optionally cognitive clarity) per day, scale 1–5 (Swift Charts).
struct MoodChart: View {
    let points: [MoodPoint]
    var showsClarity = false
    var height: CGFloat = 180

    private struct Sample: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var samples: [Sample] {
        points.flatMap { point -> [Sample] in
            guard let date = DutchFormat.day(from: point.date) else { return [] }
            var result: [Sample] = []
            if let mood = point.mood { result.append(Sample(id: point.date + "m", date: date, value: mood, series: "Stemming")) }
            if showsClarity, let clarity = point.cognitiveClarity {
                result.append(Sample(id: point.date + "c", date: date, value: clarity, series: "Helderheid"))
            }
            return result
        }
    }

    private var stride: Int {
        switch points.count {
        case ...8: return 1
        case ...31: return 7
        default: return 14
        }
    }

    var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Dag", sample.date, unit: .day),
                y: .value("Score", sample.value)
            )
            .foregroundStyle(by: .value("Reeks", sample.series))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

            if sample.series == "Stemming" {
                PointMark(
                    x: .value("Dag", sample.date, unit: .day),
                    y: .value("Score", sample.value)
                )
                .foregroundStyle(NoahColor.mood(sample.value))
                .symbolSize(points.count > 31 ? 20 : 60)
                .accessibilityLabel(Text(verbatim: DutchFormat.longDay(sample.date)))
                .accessibilityValue(Text(verbatim: "\(MoodText.label(sample.value)) (\(DutchFormat.decimal(sample.value)))"))
            }
        }
        .chartForegroundStyleScale(["Stemming": NoahColor.accent, "Helderheid": NoahColor.textSoft])
        .chartLegend(showsClarity ? .visible : .hidden)
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 3, 5]) { value in
                AxisGridLine().foregroundStyle(NoahColor.divider)
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text(verbatim: score == 5 ? "Goed" : score == 3 ? "Gem." : "Laag")
                            .font(NoahFont.caption)
                            .foregroundColor(NoahColor.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: stride)) { value in
                AxisGridLine().foregroundStyle(NoahColor.divider.opacity(0.5))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(verbatim: stride == 1 ? DutchFormat.shortWeekday(date) : DutchFormat.dayMonthShort(date))
                            .font(NoahFont.caption)
                            .foregroundColor(NoahColor.textSecondary)
                    }
                }
            }
        }
        .environment(\.locale, DutchFormat.locale)
        .environment(\.timeZone, DutchFormat.timeZone)
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Stemming per dag"))
    }
}
