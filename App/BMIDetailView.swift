import SwiftUI
import Charts
import MyOpenScaleCore

/// BMI page (pushed from the Overview BMI card): today's BMI and category, the
/// scale, the healthy range for the user's height, history over category
/// bands, the category table in kg, how it's calculated, and its limits.
struct BMIDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var range: ChartRange = .m6

    private var heightCm: Double { model.profile.heightCm }
    private var weight: Double? { model.currentWeightKg }
    private var bmi: Double? { weight.map { BodyCompositionCalculator.bmi(weightKg: $0, heightCm: heightCm) } }
    private var healthy: ClosedRange<Double> { GoalInsights.healthyWeightRange(heightCm: heightCm) }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    if let bmi, let weight {
                        hero(bmi: bmi, weight: weight)
                        BMIScaleView(currentKg: weight, goalKg: model.profile.goalWeightKg, heightCm: heightCm)
                        healthyRangeCard(weight: weight)
                        historyCard
                        categoriesCard(bmi: bmi)
                        formulaCard(bmi: bmi, weight: weight)
                        limitsCard
                    } else {
                        ContentUnavailableView("No weigh-ins yet", systemImage: "ruler",
                                               description: Text("Your BMI appears after your first weigh-in."))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("BMI")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private func hero(bmi: Double, weight: Double) -> some View {
        let category = BMICategory(bmi: bmi)
        return VStack(spacing: 4) {
            Text(bmi.formatted(1))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(category.color)
            Text(category.title)
                .font(.title3.weight(.semibold))
            Text("at \(weight.formatted(1)) kg and \(Int(heightCm)) cm")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Healthy range

    private func healthyRangeCard(weight: Double) -> some View {
        card(title: "Your healthy range", icon: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(healthy.lowerBound.formatted(1))–\(healthy.upperBound.formatted(1)) kg")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Group {
                    if weight > healthy.upperBound {
                        Text("You're \((weight - healthy.upperBound).formatted(1)) kg above the healthy range for your height.")
                    } else if weight < healthy.lowerBound {
                        Text("You're \((healthy.lowerBound - weight).formatted(1)) kg below the healthy range for your height.")
                    } else {
                        Text("You're inside the healthy range — \((weight - healthy.lowerBound).formatted(1)) kg above its lower and \((healthy.upperBound - weight).formatted(1)) kg below its upper end.")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - History

    /// BMI from the smoothed daily trend, over coloured category bands.
    private var historyCard: some View {
        let daily = WeightHistory.bucketed(model.weightHistory, by: range == .y1 ? .week : .day)
        let trend = WeightHistory.filter(
            WeightHistory.trend(WeightHistory.bucketed(model.weightHistory),
                                halfLifeDays: range.trendHalfLifeDays, centered: true),
            lastDays: range.days, now: Date())
        let points = WeightHistory.filter(daily, lastDays: range.days, now: Date())
        let toBMI = { (kg: Double) in BodyCompositionCalculator.bmi(weightKg: kg, heightCm: heightCm) }
        let values = (trend + points).map { toBMI($0.weightKg) }
        let lo = floor((values.min() ?? 20) - 1.5), hi = ceil((values.max() ?? 25) + 1.5)
        let bands: [(Double, Double, BMICategory)] = [(0, 18.5, .underweight), (18.5, 25, .normal),
                                                       (25, 30, .overweight), (30, 60, .obese)]
        return card(title: "History", icon: "chart.xyaxis.line") {
            VStack(spacing: 12) {
                if trend.count >= 2, let first = trend.first, let last = trend.last {
                    Chart {
                        ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                            if b.1 > lo && b.0 < hi {
                                RectangleMark(xStart: .value("Date", first.date), xEnd: .value("Date", last.date),
                                              yStart: .value("BMI", max(lo, b.0)), yEnd: .value("BMI", min(hi, b.1)))
                                    .foregroundStyle(b.2.color.opacity(0.08))
                            }
                        }
                        ForEach(points) { p in
                            PointMark(x: .value("Date", p.date), y: .value("BMI", toBMI(p.weightKg)))
                                .foregroundStyle(Theme.accent.opacity(0.4))
                                .symbolSize(range == .d30 ? 24 : 10)
                        }
                        ForEach(trend) { t in
                            LineMark(x: .value("Date", t.date), y: .value("BMI", toBMI(t.weightKg)))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    }
                    .chartYScale(domain: lo...hi)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 190)
                } else {
                    Text("Weigh in again to see how your BMI develops.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Categories

    private func categoriesCard(bmi: Double) -> some View {
        let current = BMICategory(bmi: bmi)
        let w = { (b: Double) in GoalInsights.weightForBMI(b, heightCm: heightCm).formatted(1) }
        let b = { (v: Double) in v.formatted(v.rounded() == v ? 0 : 1) }   // locale decimals
        let rows: [(BMICategory, String, String)] = [
            (.underweight, String(localized: "under \(b(18.5))"), String(localized: "under \(w(18.5)) kg")),
            (.normal, "\(b(18.5))–\(b(24.9))", "\(w(18.5))–\(w(25)) kg"),
            (.overweight, "\(b(25))–\(b(29.9))", "\(w(25))–\(w(30)) kg"),
            (.obese, String(localized: "\(b(30)) and above"), String(localized: "from \(w(30)) kg")),
        ]
        return card(title: "Categories", icon: "list.bullet") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 10) {
                        Circle().fill(row.0.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.0.title).fontWeight(row.0 == current ? .semibold : .regular)
                            Text("BMI \(row.1)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.2).monospacedDigit().foregroundStyle(.secondary)
                        if row.0 == current {
                            Image(systemName: "arrowtriangle.left.fill")
                                .font(.caption2)
                                .foregroundStyle(row.0.color)
                                .accessibilityLabel("You")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(row.0 == current ? row.0.color.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
                    if i < rows.count - 1 { Divider().opacity(0.4) }
                }
            }
            Text("Weights for your height of \(Int(heightCm)) cm (WHO categories for adults).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - Formula

    private func formulaCard(bmi: Double, weight: Double) -> some View {
        let m = heightCm / 100
        return card(title: "How it's calculated", icon: "function") {
            VStack(alignment: .leading, spacing: 8) {
                Text("BMI = weight ÷ height²")
                    .font(.headline.monospaced())
                Text("\(weight.formatted(1)) kg ÷ (\(m.formatted(2)) m)² = \(bmi.formatted(1))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Your height comes from Settings; update it there if it changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Limits

    private var limitsCard: some View {
        let fat = model.latestValue(.bodyFat).flatMap { $0.isFinite ? $0 : nil }
        return card(title: "What BMI doesn't show", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("BMI only relates weight to height. It can't tell muscle from fat, so very muscular people can show a high BMI while being lean — and a normal BMI can still hide a high body-fat share.")
                if let fat {
                    Text("Your scale measured a body fat of \(fat.formatted(1)) %, which says more about body composition than BMI alone.")
                        .fontWeight(.medium)
                }
                Text("It's not meant for children, during pregnancy, or for judging health on its own. Talk to a doctor for medical advice.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(title: LocalizedStringKey, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}
