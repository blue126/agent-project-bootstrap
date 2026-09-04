# Security policy

## Reporting

请使用 GitHub repository 的 **Security → Report a vulnerability** 私密报告入口。不要在 public issue、pull request、日志或聊天中发布 credential、exploit details 或 consumer private data。

报告应只包含复现所需的最小信息。请立即撤销或轮换任何可能暴露的凭据；本项目不会要求你提交真实 secret。

## Scope

安全边界包括 bootstrap managed-file upgrades、immutable pins、validation/review contracts、GitHub permissions、secret isolation、Ruleset reconciliation 和 public distribution。Consumer 项目的业务代码与项目专属 adapter 由相应 consumer 维护。

当前尚未发布正式支持周期；修复将在受审查的 pull request 和 immutable release SHA 中公布。
