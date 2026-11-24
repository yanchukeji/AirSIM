import Security
import SwiftUI

@main
struct LanU30App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var host = ""
    @State private var port = ""
    @State private var secret = ""
    @State private var keepAddress = false
    @State private var keepSecret = false
    @State private var message = "尚未查询。只会对你填写的局域网地址发送一次 GET /v1/health。"
    @State private var snapshot: HealthSnapshot?
    @State private var busy = false
    private let defaults = UserDefaults.standard
    private let keychain = KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "local.placeholder.lanu30")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("这是独立的局域网健康检查，不是 AirSIM 官方客户端，也不管理原厂网页或 UFI-TOOLS。配对密钥只留在本机钥匙串，请求里只发送签名，不发送密钥原文，也不访问中继、GitHub 或 Notion。")
                        .font(.footnote)
                }
                Section("局域网设备") {
                    TextField("IPv4，例如 192.168.1.20", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("控制端口，由你填写", text: $port)
                        .keyboardType(.numberPad)
                    SecureField("配对密钥，至少 32 字节，无默认值", text: $secret)
                    Toggle("在本机记住地址和端口", isOn: $keepAddress)
                    Toggle("把密钥存入钥匙串", isOn: $keepSecret)
                }
                if stockPortWarning {
                    Section {
                        Text("2333、8080、8443 是这台设备上已经观察到的原厂或 UFI 端口。本应用没有这些服务的已证实管理接口，不会登录。若仍填写，只会请求 /v1/health，不能把它当成原厂后台。")
                            .font(.footnote)
                    }
                }
                Section {
                    Button(busy ? "正在查询" : "读取健康状态") { Task { await query() } }
                        .disabled(busy)
                    Button("删除钥匙串中的密钥", role: .destructive) {
                        keychain.delete()
                        secret = ""
                        keepSecret = false
                        message = "已删除本应用保存在钥匙串中的密钥。"
                        snapshot = nil
                    }
                }
                Section("结果") {
                    Text(message)
                    if let snapshot {
                        LabeledContent("传输", value: snapshot.transport)
                        LabeledContent("网关类型", value: snapshot.agentKind)
                        LabeledContent("设备名", value: snapshot.deviceName)
                        LabeledContent("厂商", value: snapshot.manufacturer)
                        LabeledContent("型号", value: snapshot.model)
                        if let percent = snapshot.batteryPercent {
                            LabeledContent("电量", value: "\(percent)%")
                        }
                        if let charging = snapshot.batteryCharging {
                            LabeledContent("充电", value: charging ? "是" : "否")
                        }
                        Text("电话号码、SIM 和身份原文已从界面丢弃。身份证明通过只说明对端持有同一把配对密钥。")
                            .font(.footnote)
                    }
                }
                Section("说明") {
                    Text("本地控制使用明文 HTTP，因为仓库中的 VoWLAN 网关就是用 HMAC 签名的 HTTP，而不是 TLS。系统只放行本地网络，公网地址会被拒绝。")
                    Text("云端没有签名，也没有连接你的 U30。源码不能证明别人发布的 IPA 与这份代码相同。请在自己的 Mac 上修改 Bundle ID 并签名后再决定是否安装。")
                    Text("Required Notice: Copyright 2026 AirSIM contributors. AirSIM is licensed under the PolyForm Noncommercial License 1.0.0. Commercial use requires separate written permission from the copyright holder.")
                        .font(.caption2)
                    Text("AirSIM 名称、标志和发布通道不表示本构建获得原项目认可。")
                        .font(.caption2)
                }
            }
            .navigationTitle("本机 U30")
            .onAppear(perform: loadSaved)
        }
    }

    private var stockPortWarning: Bool {
        ["2333", "8080", "8443"].contains(port.trimmingCharacters(in: .whitespaces))
    }

    private func loadSaved() {
        if let savedHost = defaults.string(forKey: "lanu30.host") { host = savedHost }
        if let savedPort = defaults.string(forKey: "lanu30.port") { port = savedPort }
        if let stored = keychain.load() {
            secret = stored
            keepSecret = true
        }
    }

    private func query() async {
        busy = true
        defer { busy = false }
        snapshot = nil
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            message = "无法生成随机数，已取消请求。"
            return
        }
        let nonce = Base64URL.encode(bytes)
        let prepared = HealthProtocol.prepare(
            hostText: host, portText: port, secretText: secret,
            timestamp: Int64(Date().timeIntervalSince1970), nonce: nonce)
        switch prepared {
        case .failure(let error):
            message = describe(error)
        case .success(let request):
            if keepAddress {
                defaults.set(host, forKey: "lanu30.host")
                defaults.set(port, forKey: "lanu30.port")
            } else {
                defaults.removeObject(forKey: "lanu30.host")
                defaults.removeObject(forKey: "lanu30.port")
            }
            if keepSecret {
                if !keychain.save(secret) {
                    message = "钥匙串没有保存密钥，已取消网络请求。"
                    return
                }
            } else {
                keychain.delete()
            }
            let result = await LocalHealthClient().read(request: request)
            switch result {
            case .verified(let value):
                snapshot = value
                message = "身份证明通过。下面只显示非敏感字段。"
            case .httpStatus(let status):
                message = status == 401
                    ? "认证失败。密钥不匹配，或两端时间差超过 30 秒。响应正文未显示。"
                    : "对端返回 HTTP \(status)。响应正文未显示。"
            case .notHealthDocument:
                message = "没有收到本仓库记录的 JSON 健康文档。可能是端口不通、被重定向，或该端口不是兼容网关。"
            case .identityRejected:
                message = "收到响应，但身份证明没有通过。不显示设备字段。"
            case .responseTooLarge:
                message = "响应超过 8 KB，已丢弃。"
            }
        }
    }

    private func describe(_ error: HealthProtocolError) -> String {
        switch error {
        case .address(.notLiteralIPv4): return "请填写四段 IPv4，不要填写域名。"
        case .address(.notLocalNetwork): return "该地址不在局域网范围内。10、172.16–31、192.168 和 169.254 以外的地址会被拒绝。"
        case .address(.invalidPort): return "端口必须是 1 到 65535 的整数，没有预置端口。"
        case .credential(.missing): return "请填写配对密钥。本应用没有默认口令。"
        case .credential(.tooShort): return "密钥太短。请粘贴至少 32 字节的原始密钥或对应的 Base64。"
        case .credential(.rejectedDefault): return "拒绝使用常见默认口令或全零密钥。"
        case .randomUnavailable: return "随机数无效，已取消请求。"
        }
    }
}
