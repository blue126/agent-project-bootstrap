#!/usr/bin/env bash
# Match the non-interactive environment gates in skills@1.5.23. Never scrub
# these markers to make an Agent-owned process look like a human terminal.
is_agent_environment() {
  local variable
  for variable in AI_AGENT CODEX_SANDBOX CODEX_CI CODEX_THREAD_ID \
    CURSOR_TRACE_ID CURSOR_AGENT GEMINI_CLI ANTIGRAVITY_AGENT AUGMENT_AGENT \
    OPENCODE_CLIENT CLAUDECODE CLAUDE_CODE REPL_ID COPILOT_MODEL \
    COPILOT_ALLOW_ALL COPILOT_GITHUB_TOKEN; do
    [[ -z "${!variable:-}" ]] || return 0
  done
  [[ "${CURSOR_EXTENSION_HOST_ROLE:-}" == agent-exec || -e /opt/.devin ]]
}
