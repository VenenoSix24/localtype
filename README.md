# LocalType

<p align="center">
  <img src="public/icon-tauri.png" width="128" height="128" alt="LocalType Icon" />
  <br />
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Tauri-24C8DB?style=for-the-badge&logo=tauri&logoColor=white" />
  <img src="https://img.shields.io/badge/Rust-000000?style=for-the-badge&logo=rust&logoColor=white" />
</p>

**LocalType** 是一款跨设备输入增强工具，旨在将手机变为电脑的“第二键盘”。通过局域网连接，您可以在手机上舒适地输入长文本，并一键将其输入到电脑端。

希望能帮助到不习惯、不喜欢、不舒服电脑打字的大家，欢迎大家使用！！

---

## 功能亮点

- **无线文本输入**：手机打字输入，电脑即刻接收。采用 Unicode 方式，**不会占用或污染电脑剪贴板**。
- **发送模式**：类似微信、TG 的聊天流输入，支持已发送文本复制、编辑、再次发送。
- **快捷短语库**：自定义常用文本，实现高频内容一键录入。
- **界面设计**：移动端基于 Material 3 规范，支持莫奈动态取色；桌面端采用现代磨砂玻璃视觉风格。
- **外观自定义**：深色模式、多种全局配色、气泡样式、页面过渡动画、字体选择，满足定制需求。
- **安全配对**：基于 6 位动态验证码的局域网授权协议，确保连接私密安全。

---

## 快速上手

### 1. 下载安装
您可以直接前往 [GitHub Releases](https://github.com/VenenoSix24/localtype/releases) 页面下载预编译好的安装包：
- **Windows / macOS / Linux**: 下载对应系统的安装文件并运行。
- **Android / ~~iOS~~**: 下载对应系统文件至手机安装。

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
flutter build apk
```

---

## 使用提示

1. **同网环境**：确保手机和电脑连接在同一个 Wi-Fi 或局域网内。
2. **首次配对**：在桌面端开启服务后，查看显示的 6 位配对码，并在手机端输入即可完成连接。
3. **输入模式**：默认推荐使用 `Unicode` 模式，兼容性极佳且不干扰剪贴板。

---

## 许可协议

本项目基于 **MIT License** 许可协议开源。
