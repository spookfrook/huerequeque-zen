import SwiftUI

/// Signature visual piece for Huerequeque Zen:
/// A calm circular watch-like dial encoding either the configured duration or live unbreakable lock progress.
struct ZenLockDial: View {
    let progress: Double // 0...1
    let primaryText: String
    let secondaryText: String
    let tint: Color
    let tintInk: Color
    let isLocked: Bool

    private let dialSize: CGFloat = 148

    var body: some View {
        ZStack {
            // Subtle 24-tick zen watch bezel
            ForEach(0..<24, id: \.self) { index in
                let isQuarter = index % 6 == 0
                Capsule()
                    .fill(LlamaTheme.track.opacity(isQuarter ? 0.95 : 0.45))
                    .frame(width: isQuarter ? 2.0 : 1.2, height: isQuarter ? 7.5 : 4.5)
                    .offset(y: -(dialSize / 2) + 5)
                    .rotationEffect(.degrees(Double(index) * 15))
            }

            // Track ring
            Circle()
                .stroke(LlamaTheme.track, lineWidth: 6.5)
                .frame(width: dialSize - 24, height: dialSize - 24)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, min(1.0, progress))))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: dialSize - 24, height: dialSize - 24)
                .animation(.easeOut(duration: 0.25), value: progress)

            // Center readout
            VStack(spacing: 3) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tintInk)
                        .accessibilityHidden(true)
                }
                Text(primaryText)
                    .font(.system(size: primaryText.count > 5 ? 25 : 29, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(LlamaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(secondaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLocked ? tintInk : LlamaTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: dialSize, height: dialSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLocked ? "Bloqueo irrompible activo" : "Duración del bloqueo")
        .accessibilityValue("\(primaryText), \(secondaryText)")
    }
}

/// Visual daily budget bar for Allowtime: 8 calm capsules showing how much of today's allowance is spent.
struct AllowtimeBudgetBar: View {
    let usedSeconds: Int
    let budgetSeconds: Int // 0 = unlimited
    let isWindowOpen: Bool

    private let segments = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Presupuesto de hoy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LlamaTheme.muted)
                Spacer()
                Text(summaryText)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(summaryInk)
            }

            if budgetSeconds > 0 {
                let ratio = min(1.0, Double(usedSeconds) / Double(max(1, budgetSeconds)))
                let filledExact = ratio * Double(segments)

                HStack(spacing: 4) {
                    ForEach(0..<segments, id: \.self) { idx in
                        let segFill = max(0, min(1, filledExact - Double(idx)))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(LlamaTheme.sunk)
                                if segFill > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(barColor(ratio: ratio))
                                        .frame(width: geo.size.width * CGFloat(segFill))
                                }
                            }
                        }
                        .frame(height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Presupuesto diario de Allowtime")
                .accessibilityValue(summaryText)
            }
        }
    }

    private var summaryText: String {
        let usedMin = usedSeconds / 60
        if budgetSeconds <= 0 {
            return "\(usedMin) min usados · Sin límite"
        }
        let totalMin = budgetSeconds / 60
        return "\(usedMin) / \(totalMin) min"
    }

    private var summaryInk: Color {
        guard budgetSeconds > 0 else { return isWindowOpen ? LlamaTheme.warnInk : LlamaTheme.muted }
        let ratio = Double(usedSeconds) / Double(max(1, budgetSeconds))
        if ratio >= 1.0 { return LlamaTheme.badInk }
        if ratio >= 0.75 || isWindowOpen { return LlamaTheme.warnInk }
        return LlamaTheme.accentInk
    }

    private func barColor(ratio: Double) -> Color {
        if ratio >= 1.0 { return LlamaTheme.bad }
        if ratio >= 0.75 || isWindowOpen { return LlamaTheme.warn }
        return LlamaTheme.accent
    }
}
