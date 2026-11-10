import Foundation
import UIKit

// === 签到：读、签、定时、补签、记录 ===
//
// 全部走面板自己的接口（与桌面端一致）：
//   GET  /api/checkin-center                  今日进度 + 提供商账号 + 定时条目
//   POST /api/accounts/checkin  {} 或 {id}     全部签 / 单账号签
//   POST /api/auto-checkin {enabled}           定时签到总开关
//   POST /api/checkin-schedules {…}            新建或更新一条定时（带补签参数）
//   POST /api/checkin-schedules/{id}/run       立即执行
//   POST /api/checkin-schedules/{id}/delete    删除
//   GET  /api/checkin-records?limit&offset…    签到记录
//
// 注意：签到是真的在网关上跑（会开浏览器/打接口），所以每个动作都带超时，
// 失败把服务端原话抛出来，不假装成功。

extension AppModel {

    // MARK: 读

    func loadCheckin(force: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if checkinLoading { return }
        if !force, checkin != nil { return }

        checkinLoading = true
        checkinError = nil
        do {
            let response = try await authenticatedRequest("GET", "/api/checkin-center", timeout: 45)
            checkin = CheckinParser.parse(response.json)
            noteLocalCompute()
        } catch {
            let apiError = error as? PanelAPIError
            var message = apiError?.errorDescription ?? error.localizedDescription
            if let apiError, case .http(let code, let body) = apiError, code == 401 || code == 403 {
                message = body
            }
            checkinError = message
        }
        checkinLoading = false
    }

    // MARK: 签

    func checkinAll() async {
        await performCheckin(id: nil)
    }

    func checkinAccount(_ id: String) async {
        await performCheckin(id: id)
    }

    private func performCheckin(id: String?) async {
        guard activeProfile?.isValid == true else { return }
        checkinBusy = id ?? "all"
        do {
            var body: [String: Any] = [:]
            if let id { body["id"] = id }
            let response = try await authenticatedRequest(
                "POST", "/api/accounts/checkin", body: body, timeout: 150
            )
            let summary = CheckinParser.summaryText(response.json)
            toast = Toast(text: "签到完成：\(summary)", kind: summary.contains("失败 0") || !summary.contains("失败") ? .success : .warning)
            haptic(.medium)
            await loadCheckin(force: true)
            await loadAccounts(force: true)
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "签到失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        checkinBusy = nil
    }

    // MARK: 定时

    func setAutoCheckin(enabled: Bool) async {
        checkinBusy = "auto"
        do {
            let response = try await authenticatedRequest(
                "POST", "/api/auto-checkin", body: ["enabled": enabled], timeout: 30
            )
            if var center = checkin {
                center.autoEnabled = response.json.bool("enabled") ?? enabled
                checkin = center
            }
            toast = Toast(text: enabled ? "定时签到已开启" : "定时签到已暂停", kind: .success)
            await loadCheckin(force: true)
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "切换失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        checkinBusy = nil
    }

    /// 新建 / 更新一条定时签到。`id` 为空表示新建。
    func saveSchedule(
        id: String?,
        label: String,
        time: String,
        timeEnd: String?,
        enabled: Bool,
        providers: [String],
        retryTime: String,
        retryGapMinutes: Int,
        retryLimit: Int
    ) async -> Bool {
        guard !providers.isEmpty else {
            toast = Toast(text: "至少选一个提供商", kind: .warning)
            return false
        }
        checkinBusy = "schedule"
        do {
            var body: [String: Any] = [
                "id": id ?? UUID().uuidString,
                "label": label,
                "enabled": enabled,
                "time": time,
                "providers": providers,
                "retryTime": retryTime,
                "retryGapMinutes": retryGapMinutes,
                "retryLimit": retryLimit
            ]
            if let timeEnd, !timeEnd.isEmpty { body["timeEnd"] = timeEnd }
            _ = try await authenticatedRequest("POST", "/api/checkin-schedules", body: body, timeout: 45)
            toast = Toast(text: id == nil ? "定时签到已添加" : "已保存", kind: .success)
            await loadCheckin(force: true)
            checkinBusy = nil
            return true
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "保存失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
            checkinBusy = nil
            return false
        }
    }

    func deleteSchedule(_ id: String) async {
        checkinBusy = "delete-\(id)"
        do {
            _ = try await authenticatedRequest(
                "POST", "/api/checkin-schedules/\(id)/delete", body: [String: Any](), timeout: 30
            )
            toast = Toast(text: "条目已删除", kind: .success)
            await loadCheckin(force: true)
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "删除失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        checkinBusy = nil
    }

    /// 立即执行一条定时（也是「补签」的手动入口：错过窗口就用它补）。
    func runSchedule(_ id: String) async {
        checkinBusy = "run-\(id)"
        do {
            let response = try await authenticatedRequest(
                "POST", "/api/checkin-schedules/\(id)/run", body: [String: Any](), timeout: 180
            )
            let summary = CheckinParser.summaryText(response.json)
            toast = Toast(text: "已执行：\(summary)", kind: .success)
            haptic(.medium)
            await loadCheckin(force: true)
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "执行失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        checkinBusy = nil
    }

    // MARK: 记录

    func loadCheckinRecords(offset: Int = 0, append: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if checkinRecordsLoading { return }
        checkinRecordsLoading = true
        checkinRecordsError = nil
        do {
            let response = try await authenticatedRequest(
                "GET", "/api/checkin-records?limit=60&offset=\(offset)", timeout: 40
            )
            var labels: [String: String] = [:]
            for option in checkin?.providerOptions ?? [] { labels[option.id] = option.label }
            for group in checkin?.groups ?? [] { labels[group.id] = group.label }
            let parsed = CheckinParser.records(response.json, providerLabels: labels)
            checkinRecordsTotal = parsed.total
            if append {
                checkinRecords.append(contentsOf: parsed.items)
            } else {
                checkinRecords = parsed.items
            }
            noteLocalCompute()
        } catch {
            let apiError = error as? PanelAPIError
            checkinRecordsError = apiError?.errorDescription ?? error.localizedDescription
        }
        checkinRecordsLoading = false
    }
}
