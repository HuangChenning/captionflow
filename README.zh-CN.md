# CaptionFlow

**面向 macOS 的英语转简体中文实时字幕应用。**

[English](README.md)

> 状态：积极开发中。目前仓库已包含 SwiftUI 基础工程、安全的 LLM 设置，以及本地 ASR 的初步集成。

## 这是什么

CaptionFlow 面向需要理解英文视频、直播、播客和会议的人群，运行于 Apple Silicon Mac。它将本地识别英文语音，只把转写出的英文文本发送给你配置的 LLM 端点，并显示可修订的中文实时字幕。

## 隐私设计

- 麦克风和系统音频在本地处理，绝不保存原始音频。
- 只有英文转写文本和你的翻译指令会发送到所选 LLM 端点。
- API Key 保存在 macOS Keychain，不会写入 UserDefaults 或导出历史。
- 字幕与译文保留在本机，后续可导出为 UTF-8 文本。

## 预期使用流程

1. 配置兼容 OpenAI 的端点、模型、翻译指令和 API Key。
2. 选择麦克风或系统音频，只授予对应的 macOS 权限。
3. CaptionFlow 创建暂定的中英文字幕，并随上下文完善修订最新一行。
4. 最终字幕留存在本地会话历史中。

## 当前已实现

- SwiftUI macOS 应用目标，最低支持 macOS 14。
- `Caption` 领域模型与会话状态契约。
- 仅接受 HTTPS 的 OpenAI 兼容 LLM 设置界面。
- 基于 Keychain 的 API Key 安全存储。
- 已锁定 WhisperKit `v1.1.0`，用于 Apple Silicon 本地 ASR。
- LLM 翻译后端，调用兼容 Anthropic Messages 格式的端点。
- 系统本地 Translation framework 作为翻译回退：LLM 超时未返回时先用本地翻译顶上，LLM 结果到达后再修订该行。
- 覆盖字幕身份、Keychain 存储、LLM 校验、文本规范化和翻译回退逻辑的单元测试。

## 环境要求

- Apple Silicon Mac
- macOS 15 Sequoia 或更高版本（本地翻译回退依赖系统 Translation framework）
- Xcode 16 或更高版本（本项目当前使用 Xcode 27）

## 安装与使用

```bash
git clone https://github.com/HuangChenning/captionflow.git
cd captionflow
xcodegen generate
xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'
```

## 限制

第一个版本只支持英语转简体中文。不包含录音/回放、浏览器扩展、单应用音频选择、账号、计费、说话人分离及自动模型故障切换。

该应用尚未达到面向终端用户的实时转写可用状态。音频采集、模型准备、翻译请求、悬浮字幕窗和会话历史仍在开发中。

## License

许可证尚未确定。
