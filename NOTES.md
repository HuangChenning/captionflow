# CaptionFlow Notes

- CaptionFlow 是 Apple Silicon macOS 上的英语到简体中文实时字幕应用。
- 本轮交付范围是代码功能完成，不包含真实设备验收、Developer ID 签名、公证或 beta 发布。
- 本地翻译使用 Apple Translation；启动时必须检查英语到简体中文资源状态。
- LLM 用于在本地初译基础上精修；初译必须在 LLM 失败时保留。
- 术语候选可由 LLM 提出，但只能在用户确认、编辑后写入本地词库。
- API Key 仅存 Keychain；非敏感 LLM Profile 存 Application Support JSON；字幕历史可本地导出 UTF-8 文本。
