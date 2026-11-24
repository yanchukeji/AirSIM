# 本机 U30

独立的中文 iPhone 客户端，只对你填写的局域网 IPv4 做一次已签名的 `GET /v1/health`。它不是 AirSIM 官方应用，不使用原作者的 Bundle ID，也不管理原厂网页或 UFI-TOOLS。

## 它实际会做什么

- 只接受 10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、169.254.0.0/16 的字面 IPv4。域名、公网、本机回环和 100.64.0.0/10 都会被拒绝。
- 端口没有预置值。仓库里的 Android 网关源码使用 7592，MU300 文档写的是 8581；这两处都没有在你这台原厂 Android 上核实，所以不会自动填写。
- 配对密钥至少 32 字节，不提供默认口令。可以选择存入本机钥匙串，并关闭 iCloud 同步。请求只带 HMAC 签名。
- 身份证明通过后，界面只保留传输、网关类型、设备名、厂商、型号和电量。电话号码、SIM 和证明原文不进入界面模型。
- 不拨号、不发短信、不上传反馈、不检查更新、不连接中继。

明文 HTTP 是协议本身：Android 端 `VoWLANControlGateway` 在局域网上接收 HMAC 签名的 HTTP，而不是 TLS。Info.plist 只打开 `NSAllowsLocalNetworking`。

## 本机无法完成的部分

这台云端环境没有 Xcode，也没有 Apple 签名证书。这里没有生成 IPA，单元测试二进制不能安装到 iPhone。

在 Intel Mac、macOS 13 上：

1. 安装与 macOS 13 匹配的 Xcode（可用到 Xcode 15.x），并登录你自己的 Apple ID。
2. 打开 `ios-lan-u30/LanU30.xcodeproj`。
3. 修改 `ios-lan-u30/Config/Bundle.xcconfig` 里的 `LANU30_BUNDLE_IDENTIFIER`，改成你自己控制的名字。占位值 `local.placeholder.lanu30` 不能冒充原作者。
4. 在 Signing & Capabilities 里选择你的 Team。免费个人团队只能安装到自己的设备，有效期由 Apple 决定；本仓库不代为注册或付费。
5. 用数据线连接 iPhone，选择该设备，Product → Run。或 Product → Archive 后再用 Apple Configurator / Xcode Devices 安装。
6. 首次运行允许本地网络。填写设备的局域网 IPv4、你已确认的控制端口，以及在设备上生成的配对密钥。

最低系统目标是 iOS 16.0。没有假设 iPhone Air 的系统版本。

## 验证

已在 Linux Swift 6.0.3 执行：

```sh
cd ios-lan-u30
swift test
python3 scripts/static_policy_check.py
```

这不代表 Xcode 归档、签名或真机查询已经成功。当前原厂 Android 系统没有已证实的兼容网关，查询预期会失败。

## 许可

本目录是 AirSIM 的非商业衍生客户端。许可见仓库根目录 `LICENSE`，地址为 <https://polyformproject.org/licenses/noncommercial/1.0.0>。

Required Notice: Copyright 2026 AirSIM contributors. AirSIM is licensed under the PolyForm Noncommercial License 1.0.0. Commercial use requires separate written permission from the copyright holder.

AirSIM 的名称、标志、签名密钥和官方发布通道不能用来表示本构建获得原项目认可。
