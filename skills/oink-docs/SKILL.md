---
name: oink-docs
description: Use when adding, migrating, deploying, or repairing an OINK/Hugo documentation site, per-page Markdown, llms.txt, search, Mermaid, or Agent-friendly project docs.
compatibility: OpenCode with Git, Hugo/Go installation capability, and optional deployment/browser access
metadata:
  category: documentation
  scope: cross-project
---

# OINK Documentation Site

Add OINK to an existing repository with the smallest reversible change that produces a usable, tested documentation site. OINK i
s a presentation layer, not a documentation-accuracy system.

## Boundaries

- Read repository instructions before editing.
- Inspect the repository before choosing paths, CI, hosting, language, or content strategy.
- Preserve unrelated working-tree changes and existing application/infrastructure pipelines.
- Do not bulk-edit source Markdown or add front matter without approval.
- Do not introduce Node/npm solely for OINK; OINK uses Hugo Extended and Go.
- Do not commit generated output or caches.
- Keep AI gardening, runtime evidence, and automatic documentation updates out of the initial site unless explicitly requested.
- Ask before commits, pushes, PRs, deployment, secrets, DNS, or production configuration changes.

## 1. Discover

Inspect only what affects the site:

- Git state, default branch, repository visibility, and deployment authorization.
- Markdown roots, page count, structure, front matter, H1 headings, assets, raw HTML, and Mermaid.
- Existing static-site tools and CI/CD.
- Relative `.md` links and links outside the content root.
- Available Hugo Extended, Go, GitHub/hosting CLI, actionlint, and browser automation.

Report pre-existing broken links or content drift, but do not turn the pilot into a cleanup project.

## 2. Resolve Current Versions

Never copy versions from this skill. Resolve and pin a current compatible set using official sources:

- OINK releases and the selected tag's `hugo.yaml`/`theme.toml`.
- OINK installation, Agent output, and deployment documentation.
- The official OINK documentation site's current build workflow.

Commit `go.mod` and `go.sum`. Verify `hugo version` includes `+extended`; do not rely on Hugo to enforce the theme's Extended re
quirement.

## 3. Choose a Content Strategy

Use the least invasive strategy that yields non-empty browser titles, navigation labels, search entries, and Agent outputs.

### Existing OINK-ready content

Directly mount the content when pages already provide useful `title`/`linkTitle` front matter.

### Legacy Markdown

When pages have H1 headings but no front matter, do not publish blank navigation and do not immediately rewrite every source fil
e. Prefer a build-time compatibility adapter that:

1. Derives generated titles from the first H1.
2. Removes that H1 only from the generated copy to avoid duplicate headings.
3. Copies non-Markdown assets unchanged.
4. Generates missing section metadata when needed.
5. Writes to an ignored directory rebuilt on every build.
6. Maps repository edit/history links back to the real source files.

The generated tree is disposable and is never a second source of truth.

## 4. Implement the Minimal Site

Keep site-specific files together when practical. Provide:

- OINK module configuration and content mounts.
- A useful OINK data-driven homepage; a body-only home page renders empty.
- Offline search.
- Mermaid support when source content uses Mermaid.
- HTML, per-page `index.md`, Markdown alternate links, and root `llms.txt`.
- A narrow link render hook when existing source-style `.md` links require it.
- Local build, preview, upgrade, and removal instructions.
- Ignore rules for generated content, `public/`, Hugo caches, and locks.

Declare complete output arrays. Page-level Hugo `outputs` can replace kind-level outputs, so enabling Markdown must not accident
ally remove HTML, RSS, or print outputs.

For a Markdown link hook, preserve query strings and fragments, ignore absolute/protocol-relative URLs, and distinguish publishe
d pages from intentional repository-source links.

## 5. Deploy Through the Existing Platform

Use the repository's appropriate deployment platform instead of assuming GitHub Pages.

For GitHub Pages:

- Query the Pages API before deciding the public URL.
- Use `actions/configure-pages` and its `base_url` output.
- PRs build only; default-branch/manual runs may deploy.
- Build job gets read-only contents permission.
- Deploy job alone gets Pages and OIDC write permissions.
- Exchange only the Pages artifact between jobs.
- Pin Hugo Extended, Go, OINK, and action major versions.
- Use a strict clean production build and concurrency protection.

Do not change a custom domain or DNS merely because deployment succeeded but the URL failed. Compare hosting settings, DNS, CDN
response, and origin response; show the exact proposed external change and get approval first.

## 6. Verify

Run a strict clean build with warnings treated as failures. Keep smoke checks small but meaningful:

- Root HTML, root Markdown, and `llms.txt` exist and are non-empty.
- A representative page has HTML and Markdown outputs.
- Canonical and Markdown alternate URLs use the real deployment base URL.
- Representative Markdown contains expected title/body content.
- Search data contains a known page and valid deployment path.
- Mermaid produces runtime markup when applicable.
- Homepage content is visible.
- Legacy pages have non-empty browser titles and sidebar labels.
- Repository action links target real source files, not generated overlays.
- Source docs have no unintended diff.
- Workflow syntax and `git diff --check` pass.

After deployment, test the real URL at desktop and mobile widths. Exercise navigation, search, theme switching, page actions, Ma
rkdown links, and Mermaid rendering. Check current-page console errors and HTTP 200/content types for `llms.txt` and one `index.
md`.

If the browser cannot reach a container-local server, use the real preview/deployment URL instead of declaring visual verificati
on impossible.

## Completion

Report the live URL, pinned versions, changed files, whether source docs changed, build result, Agent-output checks, visual resu
lts, deployment run/PR links, deferred pre-existing defects, and rollback steps.

Do not call the work complete when CI is green but the public URL is wrong, blank, or returns 404.
