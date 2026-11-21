# Quarklite

夸克网盘不限速下载工具（Android / Windows / iOS）。Android 与 Windows 使用 [Gopeed](https://github.com/GopeedLab/gopeed)，iOS 使用基于 URLSession 的原生后台下载器，支持：

- 夸克网盘扫码登录 / Cookie 登录
- UC 网盘（实验性，Cookie 登录）：浏览 / 搜索 / 下载 / 重命名 / 移动 / 删除 / 新建文件夹
- 123 网盘：文件重命名 / 移动 / 删除（回收站）
- 网盘文件浏览、搜索（支持 AI 识别内容搜索，可直接搜照片内容词）
- 相册：自动扫描网盘内全部照片，网格浏览、全屏查看、一键下载
- 分享链接解析（提取码自动识别）、批量转存
- 批量下载（多选后一次加入队列）
- BT / 磁力链接下载（Android / Windows；iOS 可通过「发送到 Gopeed」转发远程下载）
- **发送到 Gopeed（iOS）：把下载直链发送到局域网 / 远程 Gopeed 实例，由它多线程下载**
- **上传：多文件上传、文件夹上传（保持目录结构），实时查看进度/速度，支持取消与重试**

## 下载 APK / IPA

在 GitHub Actions 页面打开最新的构建（workflow run），下载工件：

1. 打开仓库的 [Actions](https://github.com/zxeb/quarklite/actions) 页面
2. 点击最新一次成功的构建
3. 在 Artifacts 区域下载：
   - `quarklite-apk`：Android 安装包
   - `quarklite-ipa`：iOS / iPad 安装包（未签名，见下方说明）

正式版也会在 [Releases](https://github.com/zxeb/quarklite/releases) 中同时提供 APK 与 IPA。

### iOS 安装说明（未签名 IPA）

GitHub Actions 构建的 IPA **未做开发者签名**（无法直接安装），需要自签：

| 方式 | 步骤概要 |
| --- | --- |
| AltStore / SideStore | 电脑安装 AltServer → 手机安装 AltStore → 用它打开 IPA 自动签名安装（7 天有效期，免费 Apple ID） |
| Sideloadly | 电脑连接手机 → 拖入 IPA → 输入 Apple ID 签名安装（7 天有效期） |
| eSign / 爱思助手 | 手机端或电脑端导入 IPA，使用证书签名安装 |
| TrollStore | 把 IPA 改名为 `.tipa` 用 TrollStore 直接安装（免签名，支持 iOS 14.0–16.6.1 等） |

- 构建产物同时附带 `quarklite-*-ios-trollstore.tipa`（TrollStore 专用包）
- iPad 可直接安装（TARGETED_DEVICE_FAMILY 已含 iPad）
- 签名后首次启动需在「设置 → 通用 → VPN 与设备管理」信任开发者证书

## 工作原理

```
Flutter App (UI)
  ├── QuarkApi (Dart)  → drive.quark.cn / pan.quark.cn 夸克接口
  │      └─ 登录、文件列表、搜索、下载直链、分享解析、转存
  │      └─ 上传：upload/pre 预申请 → update/hash 秒传 → OSS 分片直传 → 合并 → finish
  ├── Gopeed 内核（Android / Windows）
  │      └─ 本地 REST API (127.0.0.1) 多线程下载 / BT 磁力
  └── iOS
         ├─ 默认：URLSession 原生后台下载 / 暂停恢复 / 任务持久化
         └─ 开启「发送到 Gopeed」：直链转发到远程 Gopeed（REST API）
```

- 夸克直链本身走 CDN 不限速，配合 Gopeed 多连接分片达到满速
- 下载时自动携带直链对应的 Cookie / Referer / User-Agent
- 会话 Cookie（`__puus`）每 100 分钟自动刷新，避免下载 403
- 相册使用夸克返回的缩略图地址加载，点击可全屏查看并下载原图
- 上传按服务端分片大小顺序直传 OSS，先算 MD5/SHA1 走秒传校验；
  上传页实时显示进度、速度与状态，支持取消 / 重试 / 清除已完成

## 本地构建

```bash
# 1. 编译 Gopeed 内核（需要 Go + Android SDK）
bash scripts/build_libgopeed.sh

# 2. 构建 APK
flutter pub get
flutter build apk --release
```


### iOS

- 最低系统版本为 iOS 15，支持 iPhone / iPad。
- 下载文件保存在应用 Documents/Quarklite，可在“文件 → 我的 iPhone → Quarklite”中查看。
- 首次在 macOS 构建前运行 `flutter pub get` 和 `cd ios && pod install`，并在 Xcode 中配置自己的签名团队。
- iOS 使用原生后台直链下载；开启「发送到 Gopeed」后改由远程 Gopeed 下载。

### 发送到 Gopeed（iOS）

iOS 上「我的 → 发送到 Gopeed」把下载直链发送到**设备上安装的 Gopeed iOS 版**：

1. 手机上安装并打开 Gopeed（保持前台或最近切过后台，避免被系统冻结）
2. App 内「我的 → 发送到 Gopeed」→ 点「扫描端口」自动发现本机 Gopeed
   （Gopeed iOS 内核监听 `127.0.0.1` 的随机端口，无法手动固定，只能扫描发现）
3. 扫描到后「保存」开启，此后：
   - 网盘直链、批量下载、BT / 磁力任务全部转发给 Gopeed 下载（直链自动附带夸克 Cookie / Referer 请求头，Gopeed 直接可下）
   - 下载的文件在 Gopeed 的沙箱内，到 Gopeed App 里查看 / 导出
   - 下载页显示的就是 Gopeed 的任务（暂停 / 继续 / 删除均可）

> 也支持把地址填成局域网内电脑 / NAS 上 Gopeed 的 IP 实现远程下载
> （桌面版需在设置里开启「允许局域网连接」）。
> 注意：iOS 上 Gopeed 被系统冻结（后台过久）时任务会暂停，重新打开 Gopeed 即恢复。

## 许可

本项目基于 **GPL-3.0** 协议开源。内嵌的 Gopeed 下载引擎同样为 GPL-3.0。
商用前请确认 Gopeed 的商业授权要求。

> 夸克网盘接口为社区逆向，可能随官方更新失效，请合理使用。
