import SwiftUI

/// 接入指引：先说清这台面板现在挂在哪，再解释「为什么手机连不了 127.0.0.1」，
/// 最后给出换位置部署时的三条路径。
///
/// 这一页是纯文档，但必须准确：用户照着敲命令，敲错一条就卡在那里。
struct SetupGuideView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var initialMode: ConnectionMode = .tailscale
    var onUseMode: (ConnectionMode) -> Void

    @State private var mode: ConnectionMode = .tailscale

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        deployedCard
                        whyCard
                        modePicker
                        stepsCard
                        safetyCard
                        limitsCard
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { mode = initialMode }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("接入指引")
                    .font(AuroraFont.titleLarge)
                    .foregroundStyle(Aurora.ink)
                Text("面板装在哪、手机怎么走、要用哪种认证")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
            }
            Spacer(minLength: 4)
            GlassIconButton(systemIcon: "xmark", tint: Aurora.inkSoft, diameter: 30, iconSize: 12) {
                dismiss()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: 当前部署

    private var deployedCard: some View {
        SectionCard {
            SectionTitle(
                title: "这台面板现在的样子",
                subtitle: "阿里云 · nginx 的 /a2a 前缀反代到本机 3065"
            )

            VStack(spacing: 0) {
                KeyValueRow(label: "访问地址", value: "http://your-panel.example.com", mono: true)
                KeyValueRow(label: "子路径", value: "a2a", mono: true)
                KeyValueRow(label: "认证", value: "管理员账号密码", mono: false)
                KeyValueRow(label: "链路", value: "手机 → 80 → nginx → 127.0.0.1:3065", mono: true)
            }
            .padding(.top, 8)

            Text("面板装了登录页，所以认证方式要选「账号密码」。登录前它会给一道机器校验题（altcha），App 在本地算完直接交，你不需要点任何验证码。\n\n公网的 3065 端口没有放开，也不需要放开：走 nginx 的 /a2a 前缀就够了，面板本体继续只听回环，暴露面反而更小。")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    // MARK: 为什么

    private var whyCard: some View {
        SectionCard {
            SectionTitle(
                title: "为什么不能填 127.0.0.1",
                subtitle: "C:\\Users\\Public\\Desktop\\Agent2API.lnk 只是一个指向 exe 的快捷方式"
            )

            Text("它指向 D:\\Agent2API\\agent2api.exe。双击 = 在那台 Windows 上启动进程，进程起来后在本机 127.0.0.1:3065 提供 HTTP 接口。\n\n127.0.0.1 在手机上指的是手机自己，永远到不了电脑或服务器。桌面版面板只监听回环地址，所以直接连是不通的 —— 必须先有一条把端口暴露出去的路（反代、隧道或内网直连）。")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("换到别的位置部署时，下面三条路选一条就行。")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.brand)
                .padding(.top, 8)
        }
    }

    // MARK: 方式选择

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(ConnectionMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 步骤

    private var stepsCard: some View {
        SectionCard {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode.tint.tint(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: mode.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mode.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text(mode.addressExample)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                }
                Spacer(minLength: 0)
            }

            Text(mode.summary)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps.indices, id: \.self) { index in
                    stepView(index: index + 1, step: steps[index])
                }
            }
            .padding(.top, 12)

            SmallTonalButton(text: "按这个方式新建连接", systemIcon: "plus") {
                dismiss()
                onUseMode(mode)
            }
            .padding(.top, 12)
        }
    }

    private func stepView(index: Int, step: GuideStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(mode.tint))
                    .padding(.top, 1)
                Text(step.title)
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = step.detail {
                Text(detail)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
            if let command = step.command {
                CommandBlock(text: command) { model.copy($0, label: "命令已复制") }
                    .padding(.leading, 26)
                    .padding(.trailing, 2)
            }
        }
    }

    private struct GuideStep {
        var title: String
        var detail: String? = nil
        var command: String? = nil
    }

    private var steps: [GuideStep] {
        switch mode {
        case .lan:
            return [
                GuideStep(
                    title: "确认面板在跑、端口在听",
                    detail: "两条命令都要有输出。没有 netstat 结果说明面板没起来，双击桌面快捷方式。",
                    command: "tasklist | findstr agent2api\nnetstat -ano | findstr :3065"
                ),
                GuideStep(
                    title: "把监听地址从 127.0.0.1 改成 0.0.0.0",
                    detail: "面板设置里找「允许局域网访问 / 监听地址 / bind」。如果面板没有这个开关，就只能走 Tailscale 或反代——这是唯一绕不过去的一点。"
                ),
                GuideStep(
                    title: "放行 Windows 防火墙",
                    detail: "管理员 PowerShell 里执行。不加这条，包会被静默丢掉，表现为「连接超时」。",
                    command: "netsh advfirewall firewall add rule name=\"Agent2API 3065\" dir=in action=allow protocol=TCP localport=3065"
                ),
                GuideStep(
                    title: "查电脑的内网 IP",
                    detail: "看「IPv4 地址」，通常是 192.168.x.x 或 10.x.x.x。",
                    command: "ipconfig"
                ),
                GuideStep(
                    title: "手机连同一个 Wi-Fi，填地址",
                    detail: "在 App 里新建连接，方式选局域网，地址填 http://192.168.x.x:3065。先用 Safari 打一下 /health，能看到 JSON 再回 App 里连。"
                )
            ]

        case .tailscale:
            return [
                GuideStep(
                    title: "两端都装 Tailscale，登同一个账号",
                    detail: "Windows 装官方客户端并登录；iPhone 装 App Store 版，登录同一账号。手机端要保持「已连接」。"
                ),
                GuideStep(
                    title: "在电脑上查 Tailscale 地址",
                    detail: "拿到 100.x.y.z 这种地址。这个地址在任何网络下都不变，比内网 IP 稳。",
                    command: "tailscale ip -4"
                ),
                GuideStep(
                    title: "如果面板只监听 127.0.0.1：用 serve 转发",
                    detail: "不用改面板配置。执行后手机访问 https://<机器名>.<你的tailnet>.ts.net 就能到 3065，无需写端口。",
                    command: "tailscale serve --bg 3065"
                ),
                GuideStep(
                    title: "或者把面板绑到 0.0.0.0，直连端口",
                    detail: "绑成 0.0.0.0 后，手机用 http://100.x.y.z:3065 直连。Tailscale 内部已经加密，不需要再套 HTTPS。"
                ),
                GuideStep(
                    title: "App 里填地址",
                    detail: "新建连接 → 方式选 Tailscale → 地址填 100.x.y.z:3065（走 serve 的话填机器名，勾上 HTTPS）。"
                )
            ]

        case .publicNet:
            return [
                GuideStep(
                    title: "先想清楚：真的需要公网吗",
                    detail: "公网暴露面板 = 把账号、密钥、日志一起暴露。只有在外网设备无法装 Tailscale 时才值得。"
                ),
                GuideStep(
                    title: "临时验证：cloudflared 快速隧道",
                    detail: "在电脑上执行，会直接打印一个 https://xxx.trycloudflare.com 地址，关掉窗口就失效。",
                    command: "cloudflared tunnel --url http://127.0.0.1:3065"
                ),
                GuideStep(
                    title: "长期方案：命名隧道 / frp / nginx 反代",
                    detail: "把域名反代到 127.0.0.1:3065，配好受信任的 HTTPS 证书。反向代理只做转发，面板本身不用改监听地址。"
                ),
                GuideStep(
                    title: "一定再加一层认证",
                    detail: "Cloudflare Access，或 nginx 的 auth_basic。面板令牌只是应用层凭证，挡不住扫描和暴力尝试。"
                ),
                GuideStep(
                    title: "App 里填域名",
                    detail: "方式选公网、勾 HTTPS、地址填 panel.example.com（不带端口即 443），令牌照抄面板的 x-panel-token。"
                )
            ]
        }
    }

    // MARK: 安全

    private var safetyCard: some View {
        SectionCard {
            SectionTitle(title: "三条底线")

            VStack(alignment: .leading, spacing: 8) {
                bullet("令牌等于管理员权限：只存钥匙串，不要截图发群。")
                bullet("公网入口必须 HTTPS + 额外认证，面板令牌不构成防护。")
                bullet("Tailscale 的 ACL 建议只放行自己的设备，别给整个 tailnet。")
            }
            .padding(.top, 8)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Aurora.warning)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 边界

    private var limitsCard: some View {
        SectionCard {
            SectionTitle(title: "这个 App 不会做的事")

            VStack(alignment: .leading, spacing: 8) {
                bullet("不会远程启动 agent2api.exe —— 进程控制必须在 Windows 上做。")
                bullet("不会读 C:\\ / D:\\ 里的文件，也打不开 .lnk。")
                bullet("不会改面板的监听地址，那需要在电脑上改配置。")
            }
            .padding(.top, 8)
        }
    }
}
