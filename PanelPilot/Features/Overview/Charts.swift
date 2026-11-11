import SwiftUI

// === 概览仪表盘的图表组件 ===
//
// 全部手绘（Shape / Canvas），不用 Swift Charts：
//   · 部署目标是 16.4，Swift Charts 能编译但样式喂不进 Aurora 的三色与圆角
//   · 这里要的是「点一下能选中、选中会联动」的交互，手绘反而更短
//
// 交互约定：
//   · 柱状图：点某一根柱子 → 选中它，顶部读数切成那一天的值
//   · 环形图：点图例某一行 → 对应扇区加亮，圆心换成它的占比
//   · 所有动画都用 spring，跟全站按压反馈一致

// MARK: - 趋势指标

enum TrendMetric: String, CaseIterable, Identifiable {
    case tokens
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: return "Token"
        case .requests: return "请求"
        }
    }

    func value(of point: PanelTrendPoint) -> Int {
        switch self {
        case .tokens: return point.tokens
        case .requests: return point.requests
        }
    }

    func format(_ value: Int) -> String {
        switch self {
        case .tokens: return PanelNumber.compact(value)
        case .requests: return PanelNumber.grouping(value)
        }
    }
}

// MARK: - 柱状图

/// 按天趋势柱状图：渐变柱 + 虚线网格 + 点选。
struct AuroraBarChart: View {

    let points: [PanelTrendPoint]
    let metric: TrendMetric
    @Binding var selected: Int?
    /// 关掉后点柱子不再做弹跳动画
    var animated: Bool = true

    var barAreaHeight: CGFloat = 118

    private var maxValue: Int {
        max(points.map { metric.value(of: $0) }.max() ?? 0, 1)
    }

    // MARK: 纵轴刻度
    //
    // 原来只有横向网格，没有刻度值：柱子多高、跟别人差多少全靠猜，
    // 「1 天」这种只有一个柱子的区间更是直接变成一整块蓝色，完全没有比例感。
    // 这里按 1 / 2 / 5 × 10ⁿ 取「好看」的步长，固定分 3 格（4 条线），
    // 所以刻度范围一定是步长的整数倍，柱子高度也按这个范围算，比例是准的。

    private var scale: (max: Int, step: Int) {
        let raw = Double(maxValue)
        let rough = max(raw / 3.0, 1)
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let nice: Double = normalized <= 1 ? 1 : (normalized <= 2 ? 2 : (normalized <= 5 ? 5 : 10))
        let step = max(Int(nice * magnitude), 1)
        return (step * 3, step)
    }

    /// 步长本身够大（≥ 1 万）就换算成「万」来标，避免 30000000 这种一串零
    private var usesWan: Bool { scale.step >= 10_000 }

    private var axisUnit: String {
        if metric == .tokens { return usesWan ? "Token · 万" : "Token" }
        return usesWan ? "请求 · 万" : "请求 · 次"
    }

    private func tickText(_ value: Int) -> String {
        let scaled = usesWan ? value / 10_000 : value
        return PanelNumber.grouping(scaled)
    }

    private var tickValues: [Int] {
        (0...3).map { $0 * scale.step }
    }

    private var labelStep: Int {
        let count = points.count
        if count <= 8 { return 1 }
        return Int(ceil(Double(count) / 6.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 轴名 + 单位：放在纵轴正上方，一眼知道这排数字是什么
            Text(axisUnit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Aurora.muted)
                .padding(.leading, axisWidth + 6)

            HStack(alignment: .top, spacing: 6) {
                yAxis
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        grid
                        bars
                    }
                    .frame(height: barAreaHeight)

                    axis
                }
            }
        }
    }

    private var axisWidth: CGFloat { 34 }

    /// 纵轴：4 个刻度值，和 4 条网格线一一对齐（top 线 = 上限，bottom 线 = 0）
    private var yAxis: some View {
        GeometryReader { geo in
            ForEach(Array(tickValues.enumerated()), id: \.offset) { index, value in
                Text(tickText(value))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: axisWidth, alignment: .trailing)
                    .position(
                        x: axisWidth / 2,
                        y: geo.size.height * (1 - CGFloat(index) / 3)
                    )
            }
        }
        .frame(width: axisWidth, height: barAreaHeight)
    }

    // MARK: 网格

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(Aurora.line.opacity(index == 3 ? 0.9 : 0.5))
                    .frame(height: 1)
                if index < 3 { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: 柱子

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let value = metric.value(of: point)
                let ratio = CGFloat(value) / CGFloat(scale.max)
                let isActive = selected == index

                Button {
                    if animated {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selected = isActive ? nil : index
                        }
                    } else {
                        selected = isActive ? nil : index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)

                        if isActive {
                            Text(metric.format(value))
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Aurora.brand)
                                .fixedSize()
                                .transition(.opacity)
                        }

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                isActive ? Aurora.brand : Aurora.brand.opacity(0.55)
                            )
                            .frame(height: max(3, ratio * (barAreaHeight - 16)))
                            // 只有一两天数据时，别让一根柱子糊满整张图
                            .frame(maxWidth: points.count <= 2 ? 76 : .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 横轴

    private var axis: some View {
        HStack(spacing: 5) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Text(shouldShowLabel(index) ? point.label : " ")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(selected == index ? Aurora.brand : Aurora.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func shouldShowLabel(_ index: Int) -> Bool {
        if points.count <= 8 { return true }
        return index % labelStep == 0 || index == points.count - 1
    }
}

// MARK: - 环形图

/// 环形占比图：可点选扇区，圆心显示当前选中项的占比。
struct AuroraDonutChart: View {

    let slices: [PanelStatSlice]
    let total: Int
    @Binding var selected: Int?

    var diameter: CGFloat = 150
    var lineWidth: CGFloat = 22
    var animated: Bool = true

    private var segments: [(index: Int, start: Double, end: Double, color: Color)] {
        var result: [(Int, Double, Double, Color)] = []
        var cursor = 0.0
        for (index, slice) in slices.enumerated() {
            let share = slice.share(of: total)
            guard share > 0 else { continue }
            let start = cursor
            let end = min(cursor + share, 1)
            result.append((index, start, end, Aurora.chartColor(index)))
            cursor = end
        }
        return result
    }

    private var activeSlice: (slice: PanelStatSlice, color: Color)? {
        guard let selected, slices.indices.contains(selected) else { return nil }
        return (slices[selected], Aurora.chartColor(selected))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Aurora.surfaceVariant, lineWidth: lineWidth)

            ForEach(segments, id: \.index) { segment in
                let isActive = selected == nil || segment.index == selected
                Circle()
                    .trim(from: segment.start + gap, to: max(segment.start + gap, segment.end - gap))
                    .stroke(
                        segment.color.opacity(isActive ? 1 : 0.28),
                        style: StrokeStyle(lineWidth: isActive && selected != nil ? lineWidth + 4 : lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(animated ? .spring(response: 0.4, dampingFraction: 0.85) : nil, value: selected)
                    .animation(animated ? .easeOut(duration: 0.5) : nil, value: total)
            }

            center
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }

    /// 扇区之间的细缝，靠 0.4% 的圆弧留出来
    private var gap: Double { slices.count > 1 ? 0.004 : 0 }


    private var center: some View {
        VStack(spacing: 2) {
            if let active = activeSlice {
                Text(PanelNumber.percent(active.slice.share(of: total)))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(active.color)
                    .monospacedDigit()
                Text(active.slice.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)
                    .frame(maxWidth: diameter - lineWidth * 2 - 10)
            } else {
                Text(PanelNumber.compact(total))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Aurora.ink)
                    .monospacedDigit()
                Text("总 Token")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Aurora.muted)
            }
        }
    }
}

// MARK: - 图例行（可点选 + 占比条）

struct DonutLegendRow: View {

    let slice: PanelStatSlice
    let total: Int
    let color: Color
    let active: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(slice.label)
                        .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Aurora.ink : Aurora.inkSoft)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(PanelNumber.compact(slice.tokens))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? Aurora.ink : Aurora.inkSoft)
                        .monospacedDigit()

                    Text(PanelNumber.percent(slice.share(of: total), digits: 0))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .frame(width: 36, alignment: .trailing)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Aurora.surfaceVariant)
                        Capsule()
                            .fill(color.opacity(active ? 1 : 0.45))
                            .frame(width: max(2, proxy.size.width * CGFloat(slice.share(of: total))))
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 紧凑指标块（概览 KPI 用）

/// 带彩色图标胶囊的 KPI 块：白卡 + 大数字 + 说明。
struct KPITile: View {

    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = Aurora.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Aurora.muted)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Aurora.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Aurora.line, lineWidth: 1)
        )
        .shadow(color: Aurora.cardShadow, radius: 6, y: 2)
    }
}

// MARK: - 运行态小格

/// 运行态矩阵里的一格：标签 + 值 + 可选的状态点。
struct RuntimeCell: View {

    let label: String
    let value: String
    var tint: Color = Aurora.ink
    var dot: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Aurora.muted)
                .lineLimit(1)

            HStack(spacing: 4) {
                if dot {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint == Aurora.ink ? Aurora.ink : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Aurora.surfaceVariant.opacity(0.6))
        )
    }
}
