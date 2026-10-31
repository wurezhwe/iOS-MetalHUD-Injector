# 宣传材料（Promo copy）

> 给 iOS-MetalHUD-Injector 的发帖文案。按平台分，可直接复制。
> 仓库：https://github.com/wurezhwe/iOS-MetalHUD-Injector
> 下载：https://github.com/wurezhwe/iOS-MetalHUD-Injector/releases/latest/download/MetalHUDLauncher.ipa

---

## 一句话

**不用 Mac、不用 Xcode、不越狱**，在 iPhone / iPad 上给自己装个启动器，
就能让任意 **App Store 应用** 显示实时 FPS / 帧时间。

---

## 核心卖点（发帖时反复用）

1. **痛点够痛**：设置里"开发者 → 显示图形 HUD"对 App Store 应用**根本无效**，
   因为它只认带 `get-task-allow` 权限的进程。很多人以为是自己操作错了。
2. **原理一句话**：Metal 启动时读环境变量，这条路**不查签名**。
   把 `MTL_HUD_ENABLED=1` 塞进目标进程即可。
3. **以前怎么做**：Mac 上 `devicectl`，或 Windows 插线跑 `pymobiledevice3`。
   **都得连电脑，每次测都得插线。**
4. **现在**：全程在手机上——配对、建隧道、启动，一条龙。产物是 IPA。
5. **纯 CI 出包**：Fork 一下就能通过 GitHub Actions 拿到 IPA。

---

## V2EX / 酷安 / 少数派 风格（中文）

**标题**：给 App Store 应用开 Metal 性能 HUD，现在不用电脑了

**正文**：

一直在折腾 iOS 上的帧率测量。之前的路子是 Windows 插线 + `pymobiledevice3`，
或者 Mac 上 `devicectl device process launch -e`，都能出 HUD，但每次测都得把手机
插到电脑上，很烦。

先说个很多人踩的坑：**设置 → 开发者 → 显示图形 HUD 这个开关，对 App Store 应用是无效的。**
它只对带 `get-task-allow` entitlement 的进程（Xcode 调试包、自签应用）生效。
App Store 应用没这个权限，所以那个开关对它们永远不起作用——不是你没开对。

真正的开关是环境变量：

```
MTL_HUD_ENABLED=1
MTL_HUD_SCALE=0.35          # 大小
MTL_HUD_ALIGNMENT=top-right # 位置
```

Metal 运行时在进程启动时读它们，**这条路径不检查签名**。所以只要能"带着环境变量
启动目标 App"，HUD 就有了。

于是我做了个全在设备上完成的版本：

1. 在 App 里把自己当成"可配对主机"，从 **设置 → 隐私与安全性 → 开发者模式**
   批准一下（iOS 27 起支持）；
2. 通过回环 VPN（LocalDevVPN / SideStore 自带的 WireGuard）连到设备自身的 RSD；
3. RemotePairing 完成 pair-verify，建 TLS-PSK 隧道；
4. 隧道内调 DVT / CoreDevice 的启动接口，把环境变量一起传过去。

几个实际踩到的坑，代码里都处理了：

- **不少系统版本根本不公布 `com.apple.coredevice.appservice`**（我那台只公布 63 个服务，
  里面没有它），所以启动走 DVT `processcontrol`，失败再回退 coredevice；
- 同理应用列表要靠 DVT → coredevice → InstallationProxy 三级回退；
- **DVT 返回的应用名经常只有 bundle id**，中文名全丢了 —— 所以列表会用
  InstallationProxy 的显示名去补，否则中文搜索等于没用；
- 搜索支持 **中文 / 全拼 / 首字母**（`王者荣耀`、`wangzherongyao`、`wzry` 都行），
  拼音转换只在列表加载时做一次，打字不卡。

界面是 iOS 26 的 Liquid Glass，日间夜间都适配，内置简体 / 繁体 / 英文。

Fork 仓库后 Actions 直接出未签名 IPA，SideStore / TrollStore / 自签都能装。
CI 不含任何证书。

已知限制老实说：
- 部分游戏有反调试保护，会拒绝以调试方式启动，这类无解；
- 只对 Metal 渲染的进程有效（绝大多数游戏和大量普通应用都是）；
- 没越狱的话，只能"从这个启动器启动"才有 HUD，点桌面图标启动是没有的。

仓库：https://github.com/wurezhwe/iOS-MetalHUD-Injector

---

## Reddit 风格（英文，r/jailbreak / r/sideloaded / r/iosprogramming）

**Title**: Launch App Store apps with the Metal Performance HUD injected — no Mac, no Xcode, no jailbreak

**Body**:

The "Show Graphics HUD" switch under Settings → Developer does nothing for App
Store apps, and that's by design: it only applies to processes with the
`get-task-allow` entitlement (Xcode debug builds, self-signed apps). People
reasonably assume they flipped it wrong; they didn't.

The actual switch is an environment variable:

```
MTL_HUD_ENABLED=1
MTL_HUD_SCALE=0.35
MTL_HUD_ALIGNMENT=top-right
```

Metal reads those at process start and that path doesn't consult the code
signature. Get them into the target process and the HUD appears.

Until now that meant a Mac (`devicectl device process launch -e`) or a Windows PC
with `pymobiledevice3` over USB — i.e. a cable every single time you want to
measure something.

This does it entirely on-device:

1. the app advertises itself as a pairable host; you approve a 6-digit PIN in
   Settings → Privacy & Security → Developer Mode (iOS 27+);
2. it reaches the device's own RSD through a loopback VPN (LocalDevVPN, or the
   WireGuard profile SideStore installs);
3. RemotePairing does pair-verify, then a TLS-PSK/CDTunnel tunnel;
4. inside the tunnel it calls the DVT `processcontrol` launch method (falling
   back to CoreDevice `launchapplication`) with `environmentVariables` attached.

Things that bit me and are handled in the code:

- plenty of builds do **not** advertise `com.apple.coredevice.appservice` over
  RSD — mine advertised 63 services without it — so launching goes through DVT
  first and falls back to CoreDevice;
- app listing needs the same three-way fallback (DVT → CoreDevice →
  InstallationProxy);
- **DVT often returns only bundle ids, no display names**, so the list is
  enriched from InstallationProxy; otherwise searching by app name is useless;
- search accepts Chinese, full pinyin and pinyin initials, with the conversion
  done once at list load so typing stays smooth.

UI is SwiftUI with iOS 26 Liquid Glass, light and dark, and ships in English,
Simplified and Traditional Chinese.

Fork it and GitHub Actions builds an unsigned IPA (no certificates involved);
install with SideStore, TrollStore or your own signing setup.

Honest limitations: games with anti-debug protection will refuse to start; only
Metal-rendered processes show the HUD; and without a jailbreak you must launch
from this app — tapping the Home Screen icon won't have it.

Repo: https://github.com/wurezhwe/iOS-MetalHUD-Injector

---

## X / Twitter（英文，单条 + 串）

**单条**：

App Store apps ignore the Developer → Graphics HUD switch — it only applies to
processes with `get-task-allow`. The real switch is `MTL_HUD_ENABLED=1`, which
Metal reads at launch without checking the signature.

I built an on-device launcher that injects it: no Mac, no Xcode, no jailbreak.
https://github.com/wurezhwe/iOS-MetalHUD-Injector

**串（thread）**：

1/ iOS won't show the Metal perf HUD for App Store apps. Not a bug: the Developer
toggle only applies to `get-task-allow` processes.

2/ Metal reads `MTL_HUD_ENABLED` / `MTL_HUD_SCALE` / `MTL_HUD_ALIGNMENT` at
process start. That path never checks the code signature.

3/ So the trick is launching the app *with* those variables. Before: a Mac
(`devicectl`) or Windows + `pymobiledevice3` + a USB cable. Every single run.

4/ Mine does it all on-device: pair from Settings (iOS 27), tunnel via a loopback
VPN, then call the DVT/CoreDevice launch API with `environmentVariables`.

5/ Gotchas I hit: many builds don't advertise `coredevice.appservice` (mine
showed 63 services without it) → fall back to DVT `processcontrol`. And DVT
returns bundle ids instead of app names → enrich from InstallationProxy.

6/ SwiftUI + Liquid Glass, light/dark, EN / 简中 / 繁中. Search takes Chinese,
pinyin and initials.

7/ Fork → GitHub Actions builds an unsigned IPA. SideStore/TrollStore/self-sign.
https://github.com/wurezhwe/iOS-MetalHUD-Injector

---

## 中文短版（微博 / 即刻 / 朋友圈）

不用 Mac、不用 Xcode、不越狱，就能让 App Store 应用显示实时帧率。

很多人不知道：设置里的「显示图形 HUD」对 App Store 应用是无效的，
它只认 `get-task-allow` 权限。真正的开关是环境变量 `MTL_HUD_ENABLED=1`，
Metal 启动时读取，且不校验签名。

以前得插电脑（Mac 的 devicectl 或 Windows 的 pymobiledevice3），现在全程在手机上：
在设置里批准配对 → 建隧道 → 带环境变量启动。

界面是 iOS 26 液态玻璃，中英繁三语，支持中文/拼音/首字母搜索。
Fork 一下 GitHub Actions 直接出 IPA。

https://github.com/wurezhwe/iOS-MetalHUD-Injector

---

## 发布前的检查清单

- [x] 三份 README（简 / 英 / 繁），互链
- [x] 仓库 topics 打好（20 个）
- [x] 有可下载的 Release（按版本号打 tag）
- [x] MIT 许可
- [ ] **补真实截图**（最重要，没有截图点击率极低）
- [ ] 考虑加一张 GIF：从列表点启动 → 切回游戏 → HUD 出现
- [ ] 补仓库 About 的 homepage 链接

> 注意：宣传里提到"实测可用"的部分，请只写你自己真跑通过的场景。
> 目前已知在 iPad Pro 11" (iPad14,3) 上配对与隧道打通，但应用列表与启动
> 在最近一次改动后还没有重新在你的设备上验证过 —— 发布前建议先自测一遍。
