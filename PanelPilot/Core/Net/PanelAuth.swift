import Foundation
import CryptoKit

// === 面板登录（账号密码 + altcha 工作量证明）===
//
// 为什么需要这一层：
//   桌面版面板只监听 127.0.0.1，靠 `x-panel-token` 一个头就够。
//   但装到服务器上之后，面板会强制「管理员登录」——密码会话 + 机器人校验。
//   好在它同时保留了「令牌进响应体」的通道（`x-panel-auth-mode: body`），
//   登录成功后拿到 accessToken，之后每个请求照旧带 `x-panel-token`。
//   所以客户端只需要多做「登录一次」这一步，不用接管 Cookie 会话。
//
// 机器人校验（server::altcha）：
//   领题 → 枚举 number 使 sha256(salt + number) === challenge → base64(JSON) 提交。
//   题面上限 5–10 万次，在手机上几十到几百毫秒，用户无感，不需要人工点选。

/// 服务端下发的题面。
struct AltchaChallenge: Decodable, Equatable {
    var algorithm: String
    var challenge: String
    var maxnumber: Int
    var salt: String
    var signature: String
}

/// 登录成功后的令牌对。
struct PanelSession: Equatable {
    var accessToken: String
    var refreshToken: String
    /// 秒；0 表示服务端没给（此时按 401 重新登录兜底）
    var expiresIn: Int
}

enum PanelAuthError: LocalizedError {
    case challengeUnavailable(String)
    case challengeUnsolved(Int)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .challengeUnavailable(let why): return "取登录题面失败：\(why)"
        case .challengeUnsolved(let max): return "验算没找到答案（上限 \(max) 次），面板的题目格式可能变了。"
        case .rejected(let why): return why
        }
    }
}

enum PanelAuth {

    /// 求解题面，返回提交用的 base64 负载。
    ///
    /// 逐次 `SHA256.hash` 而不是先拼字符串再比较：目标值先解成 `Data`，
    /// 循环里只做一次哈希 + 一次 32 字节比较，避免每轮都生成 64 字符十六进制串。
    static func solve(_ challenge: AltchaChallenge) -> String? {
        guard let target = Data(hexString: challenge.challenge) else { return nil }
        let salt = challenge.salt

        for number in 0...max(challenge.maxnumber, 0) {
            let input = Data((salt + String(number)).utf8)
            if Data(SHA256.hash(data: input)) == target {
                let payload: [String: Any] = [
                    "algorithm": challenge.algorithm,
                    "challenge": challenge.challenge,
                    "number": number,
                    "salt": salt,
                    "signature": challenge.signature
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
                return data.base64EncodedString()
            }
        }
        return nil
    }
}

extension Data {

    /// 十六进制字符串 → 字节。长度为奇数或含非法字符时返回 nil。
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
