import Foundation

// === 本地统计计算 ===
//
// 这一层不做任何 IO：输入是已经落到本地快照里的 `PanelStatsSummary`，
// 输出是 KPI 的派生指标（日均、每请求 Token、头部集中度、环比、峰值日…）。
//
// 为什么单独一层：
//   · 图表的每个数字都要能复算，出问题时能对着原始 JSON 核对；
//   · 换成「本地演示数据」或者「离线快照」时，计算逻辑完全一样；
//   · 可以在 CI 里用固定 fixture 跑断言（见 scripts/verify-parsers.swift）。

// MARK: - 本地指标

struct PanelLocalInsight: Identifiable, Equatable {

    enum Tone {
        case brand
        case teal
        case rose
        case ink
    }

    var id: String
    var title: String
    var value: String
    var note: String
    var tone: Tone = .brand
}

enum LocalStatsEngine {

    /// 区间对应的自然日长度（`today` / `yesterday` 都是 1 天）。
    static func days(for range: String) -> Int {
        switch range {
        case "today", "yesterday": return 1
        case "30": return 30
        case "month": return 30
        case "7": return 7
        default: return max(1, 7)
        }
    }

    /// 完全在本机算出来的派生指标。全部字段来自 `summary` 与兄弟区间，不查网络。
    static func insights(
        summary: PanelStatsSummary,
        siblings: [String: PanelStatsSummary] = [:],
        range: String
    ) -> [PanelLocalInsight] {
        var result: [PanelLocalInsight] = []
        guard summary.hasData else { return result }

        let dayCount = days(for: range)
        let dailyTokens = summary.tokens / max(dayCount, 1)
        result.append(
            PanelLocalInsight(
                id: "dailyTokens",
                title: "日均 Token",
                value: PanelNumber.compact(dailyTokens),
                note: "\(dayCount) 天累计 ÷ \(dayCount)",
                tone: .brand
            )
        )

        if summary.requests > 0 {
            let perRequest = summary.tokens / summary.requests
            result.append(
                PanelLocalInsight(
                    id: "perRequest",
                    title: "每请求 Token",
                    value: PanelNumber.compact(perRequest),
                    note: "\(PanelNumber.compact(summary.tokens)) ÷ \(PanelNumber.compact(summary.requests)) 次",
                    tone: .ink
                )
            )
        }

        // 头部集中度：第一名模型占全部 Token 的比例（本地从 models 数组算）。
        let modelTotal = summary.models.reduce(0) { $0 + $1.tokens }
        if let top = summary.models.first, modelTotal > 0 {
            result.append(
                PanelLocalInsight(
                    id: "concentration",
                    title: "头部集中度",
                    value: PanelNumber.percent(Double(top.tokens) / Double(modelTotal), digits: 0),
                    note: "\(top.label) · 共 \(summary.models.count) 个模型",
                    tone: .teal
                )
            )
        }

        // 峰值日：从按天趋势里取最大的一天（柱状图用的同一份数据）。
        if let peak = summary.trend.max(by: { $0.tokens < $1.tokens }), peak.tokens > 0 {
            result.append(
                PanelLocalInsight(
                    id: "peakDay",
                    title: "峰值日",
                    value: PanelNumber.compact(peak.tokens),
                    note: peak.label,
                    tone: .brand
                )
            )
        }

        // 环比：只在「今天 / 昨天」都拿到时给，避免拿不同长度区间硬比。
        if let yesterday = siblings["yesterday"], range == "today", yesterday.requests > 0 {
            let delta = Double(summary.requests - yesterday.requests) / Double(yesterday.requests)
            // 环比要保留正负号，不能用 percent()（它会把负值夹到 0）
            let percent = Int((delta * 100).rounded())
            result.append(
                PanelLocalInsight(
                    id: "dayOverDay",
                    title: "今天 vs 昨天",
                    value: percent >= 0 ? "+\(percent)%" : "\(percent)%",
                    note: "\(yesterday.requests) → \(summary.requests) 次请求",
                    tone: delta >= 0 ? .teal : .rose
                )
            )
        }

        return result
    }
}
