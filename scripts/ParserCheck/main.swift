import Foundation

// === 本地引擎自校验（在 macOS runner 上跑，不进 App 包）===
//
// 校验两件事：
//   1. Agent 配置的报文解析在各种形状下都能给出结果或**明确的原因**；
//   2. 统计快照能在本地算出 KPI / 趋势 / 派生指标，不依赖网络。
//
// 编译方式见 .github/workflows/local-engine-check.yml：
//   xcrun swiftc <App 源码里的纯 Foundation 文件> Scripts/ParserCheck/main.swift

var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)\(detail.isEmpty ? "" : "  → \(detail)")")
    }
}

func json(_ text: String) -> JSONValue {
    guard let data = text.data(using: .utf8), let value = try? JSONValue.decode(data) else {
        return .null
    }
    return value
}

// MARK: - Agent 配置：五种报文形状

let twoClients = """
{"clients":[
  {"id":"claude-code","name":"Claude Code","resolvedPath":"/home/u/.claude/settings.json",
   "viaGateway":true,"detectionState":"","resources":{"prompt":true,"skills":true,"mcp":false},
   "applied":{"canUndo":true}},
  {"id":"codex","name":"Codex CLI","configPath":"/home/u/.codex/config.toml",
   "viaGateway":false,"detectionState":"read_error","readError":"permission denied",
   "resources":{"prompt":true,"skills":false,"mcp":true},"applied":{"canUndo":false}}
]}
"""

var outcome = AgentConfigParser.parse(json(twoClients))
check("clients 形状被识别", outcome.shape == "clients", outcome.shape)
check("clients 解析出 2 个", outcome.clients.count == 2, "\(outcome.clients.count)")
check("第一个客户端名称正确", outcome.clients.first?.name == "Claude Code")
check("路径回落到 resolvedPath", outcome.clients.first?.path?.hasSuffix("settings.json") == true)
check("接入网关标记正确", outcome.clients.first?.viaGateway == true)
check("能力解析 prompt+skills", outcome.clients.first?.capabilities.chips == ["提示词", "Skill"])
check("可撤销标记正确", outcome.clients.first?.canUndo == true)
check("第二个客户端路径回落到 configPath", outcome.clients.last?.path?.hasSuffix("config.toml") == true)
check("读取失败原因被带出", outcome.clients.last?.readError == "permission denied")
check("读取失败状态中文正确", outcome.clients.last?.stateTitle == "读取失败")
check("读取失败不算正常态", outcome.clients.last?.stateOK == false)
check("第二个客户端能力为 提示词+MCP", outcome.clients.last?.capabilities.chips == ["提示词", "MCP"])

outcome = AgentConfigParser.parse(json(#"{"data":{"clients":[{"id":"a","name":"A"}]}}"#))
check("data.clients 被识别", outcome.shape == "data.clients", outcome.shape)
check("data.clients 解析出 1 个", outcome.clients.count == 1)

outcome = AgentConfigParser.parse(json(#"[{"id":"only","name":"Only"}]"#))
check("裸数组被识别", outcome.shape == "array")
check("裸数组解析出 1 个", outcome.clients.count == 1)

outcome = AgentConfigParser.parse(json(#"{"id":"solo","name":"Solo","detectionState":"missing"}"#))
check("单个对象被识别", outcome.shape == "single")
check("单个对象状态为未检测到", outcome.clients.first?.stateTitle == "未检测到")

outcome = AgentConfigParser.parse(json(#"{"clients":[]}"#))
check("clients 空数组不算错误", outcome.clients.isEmpty && outcome.problem == nil, outcome.problem ?? "")

outcome = AgentConfigParser.parse(json(#"{"clients":null}"#))
check("clients 为 null 时给出原因", outcome.problem?.contains("null") == true, outcome.problem ?? "nil")

outcome = AgentConfigParser.parse(json(#"{"ok":true,"result":{"agents":[{"id":"x"}]}}"#))
check("未知包装不崩、给出字段名", outcome.problem?.contains("result") == true, outcome.problem ?? "nil")

outcome = AgentConfigParser.parse(.null)
check("标量返回不崩", outcome.clients.isEmpty && outcome.problem != nil)

// 2.2.0 的 bug 复现：通用列表提取器不认 clients，会把整块当成一行
let rows = JSONRows.from(json(twoClients))
check("通用列表提取器现在认 clients", rows.count == 2, "\(rows.count)")

// MARK: - 恢复预览

let previewJSON = """
{"token":"tk_123","warnings":["密钥已隐藏"],
 "files":[{"path":"/home/u/.claude/settings.json",
           "diff":[{"kind":"same","text":"{"},{"kind":"removed","text":"old"},{"kind":"added","text":"new"}]}]}
"""
let parsedPreview = AgentPreviewParser.parse(json(previewJSON), clientID: "claude-code")
check("预览解析出文件", parsedPreview.preview?.files.count == 1)
check("预览统计 +1", parsedPreview.preview?.files.first?.added == 1)
check("预览统计 −1", parsedPreview.preview?.files.first?.removed == 1)
check("预览带出恢复令牌", parsedPreview.preview?.token == "tk_123")
check("预览带出警告", parsedPreview.preview?.warnings.count == 1)

// MARK: - 统计快照：本地解析与派生计算

let summaryJSON = """
{
  "overview":{"requests":420,"successful":410,"tokens":840000,"activeDays":7,"streak":3,
              "topModel":{"model":"claude-sonnet-4"}},
  "dailyTrend":[
    {"date":"2026-11-04","tokens":100000,"requests":50},
    {"date":"2026-11-05","tokens":120000,"requests":60},
    {"date":"2026-11-06","tokens":150000,"requests":75},
    {"date":"2026-11-07","tokens":90000,"requests":45},
    {"date":"2026-11-08","tokens":180000,"requests":90},
    {"date":"2026-11-09","tokens":100000,"requests":50},
    {"date":"2026-11-10","tokens":100000,"requests":50}
  ],
  "models":[
    {"id":"m1","model":"claude-sonnet-4","totalTokens":600000,"requests":300,"successRate":0.98},
    {"id":"m2","model":"gpt-5","totalTokens":240000,"requests":120,"successRate":0.95}
  ],
  "providers":[{"id":"anthropic","label":"Anthropic","totalTokens":600000,"requests":300}],
  "accounts":[{"id":"acc1","label":"主账号","totalTokens":840000,"requests":420}],
  "cacheRates":{"last24h":{"rate":0.874,"inputTokens":1000}}
}
"""

let summary = PanelStatsSummary.parse(json(summaryJSON), range: "7")
check("统计：请求数", summary.requests == 420, "\(summary.requests)")
check("统计：成功率", abs((summary.successRate ?? 0) - 410.0 / 420.0) < 0.0001)
check("统计：趋势 7 个点", summary.trend.count == 7, "\(summary.trend.count)")
check("统计：趋势日期缩写", summary.trend.first?.label == "11-04", summary.trend.first?.label ?? "nil")
check("统计：模型按 Token 排序", summary.models.first?.label == "claude-sonnet-4")
check("统计：缓存命中被归一化", abs((summary.cacheRate ?? 0) - 0.874) < 0.0001)
check("统计：Top 模型", summary.topModel == "claude-sonnet-4", summary.topModel ?? "nil")

let insights = LocalStatsEngine.insights(summary: summary, siblings: ["yesterday": summary], range: "7")
let daily = insights.first { $0.id == "dailyTokens" }
check("派生：日均 Token = 840000/7", daily?.value.contains("12") == true, daily?.value ?? "nil")
let perRequest = insights.first { $0.id == "perRequest" }
check("派生：每请求 Token = 2000", perRequest?.value.contains("2") == true, perRequest?.value ?? "nil")
let concentration = insights.first { $0.id == "concentration" }
check("派生：头部集中度 71%", concentration?.value == "71%", concentration?.value ?? "nil")
let peak = insights.first { $0.id == "peakDay" }
check("派生：峰值日 11-08", peak?.note == "11-08", peak?.note ?? "nil")
check("派生：7 天没有环比项", insights.first { $0.id == "dayOverDay" } == nil)

let todaySummary = PanelStatsSummary.parse(json(summaryJSON), range: "today")
let todayInsights = LocalStatsEngine.insights(
    summary: todaySummary,
    siblings: ["yesterday": summary],
    range: "today"
)
check("派生：今天/昨天环比存在", todayInsights.first { $0.id == "dayOverDay" } != nil)

check("区间天数：today=1", LocalStatsEngine.days(for: "today") == 1)
check("区间天数：7=7", LocalStatsEngine.days(for: "7") == 7)
check("区间天数：30=30", LocalStatsEngine.days(for: "30") == 30)

// 空数据不能崩，也不该编造指标
let empty = PanelStatsSummary.parse(json(#"{"overview":{},"dailyTrend":[]}"#), range: "7")
check("空统计不崩", empty.requests == 0 && empty.trend.isEmpty)
check("空统计不产出派生指标", LocalStatsEngine.insights(summary: empty, range: "7").isEmpty)

// MARK: - 结果

print("")
if failures == 0 {
    print("ALL CHECKS PASSED")
} else {
    print("FAILED: \(failures) check(s)")
    exit(1)
}
