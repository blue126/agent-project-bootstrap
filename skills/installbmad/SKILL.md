---
name: installbmad
description: 安装、更新或配置 BMAD Method。用户提到安装 BMAD、bmad method、bmad-help、BMAD 工作流或将 BMAD 集成到 Claude Code 时使用。
argument-hint: "[project-directory]"
---

# 安装 BMAD Method

在用户指定的项目目录中使用 BMAD 官方安装器。安装会下载依赖并写入项目；如果目标目录或安装模式未明确，先确认，不要默认安装到当前目录。

## 前置检查

BMAD 要求 Node.js 20.12 以上。当前环境已验证 Node.js 版本：

```bash
node --version
```

通过 `npx bmad-method install --list-tools` 列出可配置的 AI 工具。若 Node.js 版本不足，先停止并请用户升级。

## 标准流程

1. 进入用户指定的项目目录。
2. 运行 `npx bmad-method install`。
3. 按交互提示选择模块、配置和 AI 工具。
4. 检查安装器报告的安装位置、已配置工具与警告。
5. 重开所选 AI 工具，在该项目中运行 `bmad-help` 验证集成。

共享配置和辅助脚本会写入项目的 `_bmad`；针对所选 AI 工具的 skills 会写入该工具自己的 skill 目录。

## 自动化与维护

- 仅在用户明确要求非交互安装 Claude Code + BMM 时，运行 `npx bmad-method install --yes --modules bmm --tools claude-code`。
- 更新或调整已有 `_bmad` 的项目时，重新运行 `npx bmad-method install`，并在提示中选择更新或修改。
- 仅在用户明确要求预发布版本时，使用 `npx bmad-method@next install`。

## 已验证的限制

本环境的 Node.js 为 `v26.7.0`，满足版本要求；但访问 npm registry 被沙箱策略阻止，`npx bmad-method install --list-tools` 返回 `403 Forbidden`，并显示 `deny network-outbound registry.npmjs.org:443`。在具备 npm registry 访问权限的终端中执行上述安装步骤。

`uv` 缺失不会阻止安装，但依赖 Python 渲染/执行的能力（例如 `bmad-build`）在安装 `uv` 前不可用；外部或自定义模块需要 Git。
