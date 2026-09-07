# Workflow selection

Workflow frameworks are explicit, mutually exclusive execution modes.

- Known values are `none`, `github-workflow`, `superpowers`, and `bmad`.
- A generic bootstrap request selects no active workflow. Guide the user to the terminal onboarding wizard; do not choose for them or recreate it as a chat questionnaire.
- The wizard detects only `github-workflow`, `superpowers`, and `bmad`. Keep detected workflows without activating, reinstalling, or overwriting them. Detection is not permission to execute them.
- If no known workflow is found, offer installation of one known workflow or the skip option. Do not classify unknown/custom workflows. Skipping installation does not disable existing unknown rules or remove project instructions.
- Installation and activation are separate decisions. Multiple packs may be installed by explicit request outside the wizard, but only one workflow may be active for a task. Bootstrap never activates multiple workflows together.
- Activate a workflow only when the user explicitly opts in or `.agent/bootstrap.yml` records an explicit active-workflow selection. Component inventory alone is not activation.
- If instructions request incompatible workflows, stop workflow execution and ask the user to choose one.
- Selecting an active workflow is not permission to install components. Obtain an explicit installation choice, scope, and target agent first. Ordinary Skills are selected separately and installed immediately after that choice; they are not a workflow mode.
- Superpowers is the managed pack for `superpowers`, not a general third-party Skill category. BMAD is the `bmad` workflow; its installation likewise does not start a BMAD workflow.
- A selected workflow may not weaken `AGENTS.md`, safety constraints, or explicit user instructions.
- Changing an existing active selection is a deliberate configuration change and should be reviewed like code; resuming onboarding must not silently replace it.
