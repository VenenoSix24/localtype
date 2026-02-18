# LocalType

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Tauri-24C8DB?style=for-the-badge&logo=tauri&logoColor=white" />
  <img src="https://img.shields.io/badge/Rust-000000?style=for-the-badge&logo=rust&logoColor=white" />
</p>

**LocalType** 是一款跨设备输入增强工具，旨在将手机变为电脑的“第二键盘”。通过局域网连接，您可以在手机上舒适地输入长文本或管理快捷短语，并一键将其注入到电脑端的任何应用程序中。

---

## 🏗️ 功能亮点

- ⌨️ **无线文本注入**：手机键入，电脑即刻接收。采用 Unicode 模拟引擎，**不占用或污染电脑剪贴板**。
- 💬 **发送模式**：类似即时通讯应用的输入体验，支持多行文本编辑及批量历史消息管理。
- 📚 **快捷短语库**：自定义常用文本，实现高频内容一键录入。
- 📱 **动态视觉适配**：移动端基于 Material 3 规范，支持 Android 12+ 动态取色；桌面端采用现代磨砂玻璃视觉风格。
- 🔐 **安全配对**：基于 6 位动态验证码的局域网授权协议，确保连接私密安全。

---

## 🛠️ 技术实现

项目采用 **Monorepo** 模式管理，确保跨端协议的一致性：

| 组件 | 核心技术 | 职责 |
| :--- | :--- | :--- |
| **Mobile** | Flutter, Provider | 文本录入、短语管理、动态主题、局域网发现 |
| **Desktop** | Tauri, Rust, React | WSS/UDP 服务、OS 级按键模拟实现 |
| **Engine** | Rust (Enigo) | 底层系统级按键事件流转换 |

---

## 🚀 快速上手

### 1. 下载安装
您可以直接前往 [GitHub Releases](https://github.com/VenenoSix24/localtype/releases) 页面下载预编译好的安装包：
- **Windows / macOS**: 下载对应系统的安装文件并运行。
- **Android / iOS**: 下载对应系统文件至手机安装。

### 2. 从源代码编译
如果您希望自行构建项目，请确保已安装 `Rust`, `Node.js` 和 `Flutter SDK`。

#### 桌面端
```bash
cd localtype_desktop
npm install
npm run tauri build
```

#### 移动端
```bash
cd localtype_flutter
flutter pub get
flutter build apk # 或 flutter build ios
```

---

## 📌 使用提示

1. **同网环境**：确保手机和电脑连接在同一个 Wi-Fi 或局域网内。
2. **首次配对**：在桌面端开启服务后，查看显示的 6 位校验码，并在手机端输入即可完成连接。
3. **注入模式**：默认推荐使用 `Unicode` 模式，兼容性极佳且不干扰剪贴板。

---

## 📄 许可协议

本项目基于 **MIT License** 许可协议开源。

Made by [VenenoSix24](https://github.com/VenenoSix24).
