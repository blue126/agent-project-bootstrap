# Superpowers integration

Superpowers is a managed upstream dependency, not vendored source and not a fork.

The known-good release is pinned in `integration.yml`. A new upstream release does not automatically change bootstrapped projects. To promote an update:

1. Compare the latest stable upstream release with the pinned ref.
2. Review release notes and workflow-selection compatibility.
3. Validate installation and representative workflow behavior on supported agents.
4. Update both `tag` and the immutable commit `ref` in `integration.yml` in a reviewed pull request.

Activation is explicit and project-local. Selecting Superpowers records that workflow in `.agent/bootstrap.yml`, but does not authorize installation. Before installing, ask the user to confirm Superpowers, the installation scope, and the target agent; then use the upstream instructions and pinned ref. Never bulk-install it merely because bootstrap was requested.

Superpowers and repository Skills may both be installed when the user explicitly chooses both. Installation does not change the workflow-selection rule: only one of `github-workflow` and `superpowers` may be active for a task.

In the standard bootstrap flow, present this integration only after the user selects the `superpowers` workflow. Do not present it as a peer category beside all Curated Skills, and do not offer inactive installation unless the user explicitly asks for both workflow packs.
