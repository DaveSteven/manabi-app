# Manabi iOS

原生 SwiftUI JLPT 专项练习应用。暖樱花粉配色，iOS 26 使用系统玻璃导航和材质，iOS 18 提供半透明材质兼容样式。支持 iPhone 和 iPad。

## 打开工程

使用 Xcode 26 打开 `Manabi.xcodeproj`，选择 Manabi scheme 和可用 iPhone 模拟器，运行即可。工程文件已生成，无需安装第三方 Swift 包。

工程定义位于 `project.yml`。增加文件或修改工程设置后运行 `xcodegen generate` 重新生成；普通 Swift 代码修改可直接在 Xcode 中进行。

如果 Xcode 刚更新、SDK 对应的模拟器尚未装好，可以使用项目附带脚本，自动选择已安装的 iPhone 模拟器：

```sh
python3 scripts/run_simulator.py
python3 scripts/run_simulator.py --test
```

脚本仅在必要时临时调整资源编译使用的运行时，结束后恢复原设置。支持 `--device <模拟器 UUID>`。模拟器构建使用本地临时签名，以保证 Keychain 正常工作，不需要 Apple 开发证书。不要用 `CODE_SIGNING_ALLOWED=NO` 运行带 Keychain 的版本。

真机运行需在 Signing & Capabilities 中选择你的开发团队，并按需要设置唯一 Bundle ID；当前未配置个人签名证书。

## 学习服务

默认连接 `http://127.0.0.1:8001`，对应同级 `manabi_api`。先在服务端目录启动 `docker compose up -d`。

模拟器与本机共用网络，可直接连接上述地址。App 的“我的 → 学习服务设置”可更换服务根地址，不包含 `/api/v1`。真机需要可访问的 HTTPS 服务，或另外配置局域网服务监听和相应开发网络例外；当前服务端默认只绑定电脑本机。

首次启动必须登录内部账号后才能使用。token 保存在 Keychain，并按服务地址隔离；有效会话可在重启后恢复。退出或凭证失效后返回登录页，旧游客凭证不再接受。App 注册入口保持关闭。

## 已接入的功能

- N2/N3 等级切换，词汇、语法、阅读、听力分类及真实题型目录。
- 选择 5/10/20 道题开始专项练习，按服务端返回的实际题数显示进度。
- 材料与关联子题、日文富文本、可放大图片、听力播放及进度拖动。
- 提交答案、对错反馈、解析与译文、点击字幕定位音频。
- 中途退出后恢复，完成结果页、逐题回顾。
- 错题按等级和题型筛选、复习与已答对记录。
- 内部账号登录、注销、学习统计和分页练习历史；App 注册入口暂时关闭。

创建练习使用持久化的幂等请求 key，失败后重试复用原 key。作答请求失败时锁定原选项，重试不会重复计分。账号 token 不写入 UserDefaults 或日志。

## 代码结构

- `Manabi/App`：入口、共享状态与导航。
- `Manabi/Networking`：API 和 Keychain。
- `Manabi/Models`：与服务端 snake_case JSON 对应的 Codable 模型。
- `Manabi/Features`：练习、错题、账号与设置页面。
- `Manabi/Components`：富文本、听力和配图组件。
- `Manabi/Design`：主题、按钮和卡片。
- `scripts/make_icon.swift`：使用原生绘图生成图标，可重新运行。

## 验证

`ManabiTests` 的 4 项测试覆盖服务地址校验、JSON 解码、幂等请求字段和重复答案不重复计数。`ManabiUITests` 的 3 项测试使用运行中的真实 API 验证强制登录、退出与会话恢复、完整答题、重启续练、阅读材料和听力播放；测试 token 与普通使用的 token 分开保存。

```sh
xcodebuild -project Manabi.xcodeproj -scheme Manabi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test
```

测试需要 Manabi 服务可访问。构建日志、测试结果和截图放在忽略提交的 `artifacts` 目录。

## 当前范围

本版优先实现在线专项练习。尚未提供离线题库下载、支付、推送、账号找回或 App Store 发布配置。当前版本不请求通知、相册或麦克风权限。
