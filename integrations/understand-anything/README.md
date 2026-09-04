# Understand Anything 集成

Understand Anything 是受管理的项目级上游集成。它不会被复制到 `skills/`，不会使用上游的全局安装器，也不得写入用户级 Skill 或插件目录。

标准 bootstrap 流程会把它作为可选项提供。用户选择后，安装器将 immutable known-good ref 克隆到 `.agent/runtime/understand-anything/repo`，应用已记录的项目路径兼容与 Git hardening 补丁，并在 `.agents/skills/` 中为其 Skills 创建相对链接。

`.agent/runtime/.gitignore` 会忽略 runtime checkout；相对 Skill 链接和 `.agent/bootstrap.yml` 会记录项目级选择。新的 checkout 可以通过重新运行 pinned installer 恢复 runtime。

提升上游版本前：

1. 审查安全报告和 release notes。
2. 验证 tag 仍解析为记录的 immutable commit。
3. 检查上游是否已吸收本地补丁，再决定重放或移除补丁。
4. 验证 Codex 的项目级发现，以及代表性的分析和 dashboard 流程。
5. 只通过经过审查的 pull request 更新 tag 和 ref。

仅在代码内容以及已有 `.ua/` 或 `.understand-anything/` 数据可信的仓库中使用该集成。
