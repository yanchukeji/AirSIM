# 源码审计与安装边界

审计对象是本仓库当前 `main` 提交 `1855e435aa1e207e6939c525c3feea4bba09ee2b`。审计时 `git ls-remote` 看到的 `https://github.com/kai-wu-cortex/AirSIM` `HEAD` 与该提交相同。这只说明这一刻 fork 的这个提交和上游 HEAD 一致，不能说明以后不会分叉，也不能说明 GitHub Release 里的 IPA/APK 与这份源码逐字节相同。

本文件不能证明没有后门。检查方式是检索网络地址、凭据、下载执行、权限和依赖清单，并阅读对应实现。没有逐行阅读全部通话音频和历史文档。未在真机、模拟器或签名环境中运行原 iOS 工程。

结论先写在这里：已定位的外联都能对应到源码里的产品功能，没有发现无法解释的隐藏域名或硬编码设备口令。原客户端仍然会在用户操作或维护者 Bundle ID 下联系项目方的 Relay、GitHub 和反馈服务。别人发布的安装包未被核对。因此不要安装未经你自己从这份源码构建并签名的包。本仓库新增的 `ios-lan-u30` 排除了这些外联，但云端没有 Xcode，没有生成 IPA，也没有连接 U30。

## 许可证

| 结论 | 证据 | 等级 | 状态 |
| --- | --- | --- | --- |
| 项目是 PolyForm Noncommercial 1.0.0，不是 OSI 开源 | `LICENSE` 全文；`README.md` 第 27 行写明商业用途需要另行书面许可 | 低 | 已证实 |
| 再分发必须带许可条款或 URL，以及 `Required Notice` | `NOTICE` 第 3–5 行 | 低 | 已证实 |
| 不得用 AirSIM 名称暗示非官方构建获得认可 | `NOTICE` 第 5 行 | 低 | 已证实 |
| `euicc-go` 为 MIT，Wrangler 依赖保持各自许可 | `THIRD_PARTY_NOTICES.md`；`module/module-agent/go.sum` 第 1 行锁定 `github.com/damonto/euicc-go v1.1.2` | 低 | 已证实 |

新客户端在 `ios-lan-u30/README.md` 和关于文案中保留了 Required Notice，显示名是「本机U30」，Bundle ID 由 `ios-lan-u30/Config/Bundle.xcconfig` 配置，占位值为 `local.placeholder.lanu30`。

## 网络端点与数据流

| 端点或行为 | 证据 | 会发送什么 | 等级 | 状态 |
| --- | --- | --- | --- | --- |
| 维护者 Relay `https://airsim-push.remotepilot.site`；旧地址 `https://push.remotepilot.site` 会被改写到前者 | `iOS/AirSIM/VoIPPushController.swift` 第 229–244 行。仅当 Bundle ID 为 `com.eric3u.airsim` 且用户没有可用地址时回退 | 设备注册、VoIP token、命令和媒体走 Relay。工程里的默认构建值是空字符串：`iOS/AirSIM.xcodeproj/project.pbxproj` 第 772、798 行 | 高 | 已证实 |
| 手动反馈上传到同一 Relay 的 `/v1/feedback` | `iOS/AirSIM/AirSIMSetupView.swift` 第 1796–1804 行；Android `FeedbackUploader.java` 第 22、48–71 行 | iPhone 型号、系统版本、Android 型号、SDK、连接模式、最长约 40 万字符的桥接日志。触发器不是 `manual` 时在采集前返回 | 高 | 已证实 |
| Worker 把反馈写入 Notion | `push-relay-worker/src/feedback.mjs` 第 153–214 行；`index.mjs` 第 89 行路由 | 日志文件、PCM 统计、用户描述。令牌来自 Worker Secret，不在仓库 | 高 | 已证实代码路径；线上是否配置令牌未验证 |
| GitHub 应用更新检查，不自动下载 IPA | `iOS/AirSIM/AppUpdateController.swift` 第 78–82 行；Android `AppReleaseClient.java` 第 18 行 | 匿名请求 Release 列表。User-Agent 为 `AirSIM-App-Update` | 中 | 已证实 |
| AVF 安装命令把 GitHub 上的 `install-avf.sh` 管道给 `sudo sh` | `android/phone-control-app/src/com/airsim/phonecontrol/AVFStartupPolicy.java` 第 17–20 行。版本字符串是 v0.4.6，README 正文已写 v0.4.7 | 在 Android 虚拟终端里远程执行上游脚本。iOS 客户端不执行这条命令 | 高 | 已证实源码；本审计没有执行 |
| Agent 更新下载 Debian 包并交给本地 installer | `AgentReleaseManager.java` 第 18–36 行 | 从 `releases/latest` 下载包和签名 | 高 | 已证实源码 |
| 用户配置的 Bark、Discord、Slack、企业微信、飞书、Telegram、QQ、Webhook | `AirSIMSetupView.swift` 第 1523 行起；`NotificationForwarder.java` 第 102–181 行。Bark 空地址会落到 `https://api.day.app/push` | 短信或来电通知正文，仅在用户保存转发目标且通道允许时 | 高 | 已证实 |
| 局域网 VoWLAN 控制，默认端口 7592 | `VoWLANGatewayService.java` 第 33 行；`VoWLANControlGateway.java` 第 54–83、258–288 行 | HMAC 签名的 HTTP。密钥不放在 URL。`/v1/health` 响应含号码、SIM 和电量，见第 136–149 行 | 中 | 已证实协议；你的原厂系统是否在听该端口未验证 |
| 纯本地模式可关闭 Relay | `RelayEgressGate` 与反馈上传第 1805 行的判断 | 关闭后反馈上传返回本地提示 | 中 | 已证实代码；默认是否已打开取决于用户设置，未在设备上核实 |
| 文档中的自建 Relay IP `https://118.178.109.247` | `docs/reviews/2026-11-03-ecs-relay-deployment.md` | 只出现在回顾文档，不是 iOS 默认地址 | 中 | 已证实文档；该主机现在是否在线未验证 |

新客户端只构造 `http://<私网IPv4>:<用户填写端口>/v1/health`，并拒绝跳转。见 `ios-lan-u30/Sources/LanU30Core/HealthProtocol.swift` 与 `LanU30App/HealthClient.swift`。

## 凭据、设备数据和日志

| 项目 | 证据 | 等级 | 状态 |
| --- | --- | --- | --- |
| VoWLAN 密钥可按设备写入钥匙串，可访问性为首次解锁后、仅本机 | `iOS/AirSIM/VoWLANAuth.swift` 第 86–142 行 | 低 | 已证实 |
| 同一文件仍保留一份不带 agent ID 的旧钥匙串项 | `VoWLANAuth.swift` 第 154–196 行 | 中 | 已证实有迁移代码；旧数据是否还在某台手机上未验证 |
| 反馈描述和备注写入 UserDefaults 键 `feedback_upload` / `airsim.feedback-*` | Android `FeedbackUploader.java` 第 24–27 行；iOS 第 1794–1795 行 | 中 | 已证实 |
| 健康和状态接口会返回号码与 SIM | `VoWLANControlGateway.java` 第 145–147 行；`StandaloneAgentGateway.java` 第 48–59 行的 `/api/health` 也带 `sim_slots` | 高 | 已证实响应字段；没有把真实号码写入本仓库 |
| 调试与反馈快照会带厂商、型号和桥接日志 | `StandaloneAgentGateway.java` 第 68–86 行 | 高 | 已证实 |
| 仓库检索没有发现私钥材料、云厂商访问密钥或写死的设备口令 | 对 `BEGIN PRIVATE KEY`、`AKIA`、常见令牌前缀的检索只命中文档和示例配置中的占位说明 | 中 | 已证实检索范围内没有；不能覆盖加密或发布资产 |
| 新客户端拒绝 `admin`、`password` 等短默认值，密钥不进入健康界面模型 | `CredentialPolicy.swift`、`HealthProtocol.swift` 的解析白名单；测试 `LanU30CoreTests` | 低 | 已证实单元测试 |

## 权限和 entitlements

原 iOS 主目标 `iOS/AirSIM/AirSIM.entitlements` 第 5–12 行申请 App Group、推送环境、通话和短信能力。`Info.plist` 第 57–85 行允许本地网络明文、通讯录、蓝牙、麦克风，以及音频、蓝牙、VoIP 和远程通知后台模式。Bundle ID 占位是 `com.example.airsim`（`project.pbxproj` 第 777 行附近），维护者发布说明使用过 `com.eric3u.airsim`。这些权限和原作者的推送身份不能由新客户端继承。

新客户端的 Info.plist 只有本地网络说明和 `NSAllowsLocalNetworking`。没有麦克风、通讯录、蓝牙、定位或推送 entitlement。

## 依赖与锁文件

| 文件 | 观察 | 等级 | 状态 |
| --- | --- | --- | --- |
| `push-relay-worker/package-lock.json` | lockfileVersion 3，直接开发依赖为 Wrangler 4.124.0，其余为传递依赖并带 integrity | 中 | 已看到锁文件；没有重装或审计每个传递包 |
| `push-relay-worker/self-hosted/package-lock.json` | 另一套 Worker 运行时锁文件 | 中 | 未逐项核对 |
| `module/module-agent/go.sum` | 含 euicc-go、testify、yaml | 中 | 已看到条目；没有运行 `go mod verify` |
| iOS 工程 | 没有 CocoaPods / SwiftPM 清单，系统框架由 Xcode 工程引用 | 低 | 已证实没有第三方 Swift 包清单 |
| 新客户端 | 不依赖 Swift 包。HMAC 与 SHA-256 在 `ios-lan-u30/Sources/LanU30Core`，用已知答案测试 | 低 | 已证实 `swift test` |

## 远程下载、更新和执行

除上文的 `curl | sudo sh` 与 Agent 包下载外：

- `android/phone-control-app/build.sh` 在构建机上按固定校验和下载 Maven 上的 Shizuku 与 AndroidX。这是构建期行为。
- `ShizukuBridgeManager.java` 第 25 行只保存 Shizuku 官方下载页 URL，供用户自行安装，不是静默执行。
- Android 根桥 `RootBridgeTransport.java` 第 64–67 行会在存在 `su` 时启动 `app_process`。这是有 root 时的音频桥，不是 iOS 路径。你的设备此前观察为 `uid 2000`、没有 `su`。本审计没有尝试获取 root。
- `module/module-agent/main.go` 存在本地 `/api/esim/download` 路由。本审计没有把它展开为完整的 eSIM 实现，新客户端也不调用它。

## 构建和发布链

README 与 `docs/releases/` 指向 `kai-wu-cortex/AirSIM` 的 GitHub Release、TestFlight 和维护者 Relay。发布说明记录过未签名 IPA 必须重签。仓库 `.gitignore` 排除了 `*.ipa`、`*.p8`、`*.mobileprovision` 和 `*.key`。工作区没有这些二进制。

因此：源码审计不能证明任何一个已发布 IPA、APK 或 TestFlight 构建与 `1855e435` 相同，也不能证明签名者没有在打包时加入源码以外的内容。

## 新客户端的明文 HTTP

`VoWLANControlGateway` 用 TCP 直接读 HTTP/1.1，认证靠 `x-airsim-vowlan-*` HMAC，时间窗 30 秒（`VoWLANAuth.java` 第 11、33–39 行）。新客户端沿用这个已实现的 `GET /v1/health`，不增加第二套管理 API。ATS 只放行本地网络。公网明文 HTTP 不会被构造出来，因为地址必须先通过私网判断。

2333、8080、8443 没有出现在本仓库的设备协议里。新客户端不登录这些端口；用户如果手工填入，界面会提示这不是已证实的管理接口，请求仍然只有 `/v1/health`。

## 风险汇总

| 等级 | 已证实 | 处理 |
| --- | --- | --- |
| 高 | 原应用的 Relay、反馈、通知转发、远程安装脚本、健康响应中的号码 | 不建议安装原发布包。新客户端不包含这些路径，并丢弃号码字段 |
| 中 | 更新检查、钥匙串迁移项、依赖锁文件未逐包复核、文档中的历史公网 IP | 新客户端不检查更新，不连接该 IP |
| 低 | 许可和署名、本地网络 ATS、构建期依赖下载 | 新客户端保留署名 |

可疑但已有解释：反馈和 Relay 看起来像外传，源码把它们做成手动或配置后的功能，并在纯本地模式拒绝反馈上传。这不是未解释的隐蔽通道，但仍然不适合作为「只留在局域网」的日常客户端。

未验证：

- Release 资产与本提交的一致性。
- 维护者 Relay、Notion 和 `118.178.109.247` 的当前线上内容。
- 你的 U30 是否监听 7592，或 `/v1/health` 是否返回本仓库描述的 JSON。
- UFI-TOOLS 2333 和中兴 8080/8443 的登录协议。完整登录此前未验证，本审计没有探测设备。
- 原 iOS 工程在 Xcode 中能否签名。云端没有 Xcode。

## 安装建议

不要安装本仓库以外的 AirSIM IPA/APK，也不要把本次源码审计当成对那些文件的清洁证明。

`ios-lan-u30` 是一份可以在你自己的 Mac 上签名的局域网客户端。云端没有产出 IPA，路径不存在。单元测试产物 `ios-lan-u30/.build/` 是 Linux 测试运行文件，不能安装到 iPhone，也不应提交。安装步骤见 `ios-lan-u30/README.md`。在你的原厂 Android 上，这次查询预期找不到兼容网关。

## 补充：airsim-mu300 能否装到这台 U30 Air

只读核对了公开仓库 `kai-wu-cortex/airsim-mu300`，提交 `d4cc2d7eb4893c2810e4d65beac0367a9b9b2422`（2026-11-08，说明为 Release R23 preview）。没有克隆后执行安装脚本，没有连接设备，没有刷写或重启。

**结论：对当前正在运行的原厂 Android 13 系统，不支持直接安装。** 这不是改一个包名就能完成的条件适配。发布包要求另一套已启动的 mu300-linux OpenWrt，并且以 root 安装。你已说明不做固件重刷；即便设备里另有一个尚未观察到的 Linux 系统，本审计也没有证据，不能把型号同名当成已经兼容。

已核实的设备事实与仓库要求并不在同一层：

| 已观察到的设备 | 该提交的安装要求 |
| --- | --- |
| ZTE U30 Air，Android 13，固件名 U30Air_SSV1.0.0B14，T760 | 支持表写的是 U30 Air 上的 mu300-linux v2026.10.30.1 / OpenWrt 25.12.6，内核必须等于 `5.4.254-gb50db5b6224c`，内核配置 SHA-256 必须等于 `1057cb97e0d2d7f26816e8bf7841faac1153833a01d4893cdc196b75ae6356b3`。见 README「支持环境」和 `scripts/install.sh` 第 21–23 行 |
| 引导锁定，adb shell 为 uid 2000，没有 su | `scripts/install.sh` 第 15–19 行要求 root、`uname -m` 为 aarch64、`apk-tools 3`，以及 `mu300-at`、`ubus`、`jsonfilter` |
| 已装 UFI-TOOLS 4.0.0，包名 `com.minikano.f50_sms`，网页端口 2333；原厂 `com.zte.web` 在 8080/8443 | README 第 25 行写明这是 LuCI 插件、Linux Agent 和音频桥，不是 Android APK，也不是完整系统镜像。`docs/DEPLOYMENT.md` 第 20 行再次写明软件包是 OpenWrt APK v3，不是 Android APK |

不能把 MU300 和这台 U30 Air 画等号。README 第 20 行写明 F50 / 7.2.8 尚未适配，F50 在另一分支；第 25 行把目标限定为「运行 mu300-linux OpenWrt 的 U30 Air」。已安装应用的包名里含有 `f50`，这只证明装了这个 Android 包，不能证明硬件就是 F50 分支，也不能证明可以改用本 Release。设计文档 `docs/U30AIR_AIRSIM_DESIGN.md` 第 14–18 行把正式实现放在 OpenWrt，并写后续 Android 形态需要 root 和匹配原厂内核的音频驱动，普通 APK 不够。`docs/UFITOOLS_PLUGIN_DESIGN.md` 开头标明是 2026-10-26 的未经验证草案，安装入口依赖 UFI 的 root shell 和 Magisk/KernelSU。README 第 170 行把 UFI Tools 文档标为历史探索，不代表当前已发布功能。

安装器还会从 `https://github.com/kai-wu-cortex/airsim-mu300/releases/download/v0.1.0-r23/` 下载包和公钥，校验后写入 `/etc/apk/keys` 并 `apk add`（`scripts/install.sh` 第 52–84 行）。音频准备可能要求重启进入 OpenWrt。`scripts/fetch-firmware.sh` 第 8–31 行从 `dikeckaan/mu300-audio-firmware` 取 `agdsp.bin`，上游许可在文档中标为未声明。卸载脚本 `packaging/openwrt/pre-deinstall` 会停止服务并挪动启动项。这些都是 root 级系统改动，不是 Android 应用安装。

更新器只接受 GitHub 发布域名（`cmd/airsim-mu300d/updates.go` 第 246–255 行），这能解释下载来源，但不能让它在没有 root 和 OpenWrt 工具的 Android 上安装。管理端口 `127.0.0.1:7581`、内部 Agent `8575` 与配对端口 `8580–8582` 属于该 Linux 系统，和现在的 2333/8080/8443 不在同一系统里，不构成「装进 UFI」的依据。

仍需要、且本次没有做的只读核对：在设备上查看 `getprop ro.build.display.id`、`ro.product.cpu.abi`、`ro.hardware` 和 `uname -r`。T760 与设计文档中的 UMS9620 是否为同一平台，源码没有给出对应关系。是否存在另一套可启动的 OpenWrt，也没有证据。这些核对也不包括解锁、切启动项或刷写。
