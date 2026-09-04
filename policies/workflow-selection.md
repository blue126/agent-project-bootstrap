# Workflow selection

Workflow frameworks are explicit, mutually exclusive execution modes.

- Allowed values are `none`, `github-workflow`, and `superpowers`.
- A generic bootstrap request selects nothing; ask the user when the active workflow is unspecified.
- Activate a workflow only when the user explicitly opts in or `.agent/bootstrap.yml` selects it.
- Never activate `github-workflow` and `superpowers` together for the same task.
- If instructions request both, stop workflow execution and ask the user to choose one.
- Installation and activation are separate decisions. Repository Skills and Superpowers may both be installed when explicitly requested, but only one workflow may be active.
- Selecting a workflow is not permission to install its components. Obtain an explicit installation choice, scope, and target agent first.
- In the standard flow, offer the Superpowers installation only when `superpowers` is the selected workflow. Installing an inactive workflow pack is an advanced action requiring an explicit request.
- A selected workflow may not weaken `AGENTS.md`, safety constraints, or explicit user instructions.
- Changing the project selection is a deliberate configuration change and should be reviewed like code.
