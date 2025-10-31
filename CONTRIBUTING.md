<p align="center">
  <img src="docs/img/contributing-cover.png" alt="Contributing to Freetracer section header" width="860">
</p>

# Contributing to Freetracer

Thanks for your interest in helping Freetracer! 🎉 We’re a privacy-first, offline image flasher and we welcome contributions of all kinds—code, docs, design, testing, and thoughtful feedback. This guide keeps things friendly and efficient so you can spend time improving the project, not guessing the process. Thanks so much again for considering to contribute to Freetracer! ❤️

---

## Quickstart (TL;DR)

1. Please be a respectful and kind.
2. Pick a contribution path: file an issue, polish docs, test the UI, work on a new feature or improve logic/security.
3. For code changes:
   - Install prerequisites listed in `README.md`.
   - Format touched Zig files with `zig fmt path/to/file.zig` or `zls` lsp.
   - Populate the `./src/env.zig` and `./macos-helper/src/env.zig` using env.example.zig.
   - Run `zig build test-lib`, `zig build test-helper`, and `zig build test` (they’re quick).
   - Build or run locally with `zig build run` or `zig build -Dtarget=aarch64-macos --release=safe bundle` for complete bundle.
   - For an end-to-end test, both the helper binary and the app bundle must be codesigned.
4. Open a PR using our [template](#pull-request-checklist) and note any security / privacy considerations.
5. Need help? Ask in issues or discussions — maintainers aim to respond quickly.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
  - [Report a Bug](#report-a-bug)
  - [Suggest an Enhancement](#suggest-an-enhancement)
  - [Improve Docs, Design, or UX](#improve-docs-design-or-ux)
  - [Work on Code](#work-on-code)
- [Getting Started with Development](#getting-started-with-development)
  - [Local Setup](#local-setup)
  - [Testing & QA](#testing--qa)
  - [Architecture Overview](docs/architecture-overview.md)
  - [Security & Privacy](docs/security-and-privacy.md)
- [Issues & Discussions](#issues--discussions)
- [Pull Request Checklist](#pull-request-checklist)
- [Reviews & Support](#reviews--support)
- [Security Disclosures](#security-disclosures)
- [Additional Resources](#additional-resources)

---

## Code of Conduct

Please be respectful, kind and patient, assume positive intent, and keep feedback constructive. If you experience or witness unacceptable behavior, please email `community@orbitixx.com`.

---

## Ways to Contribute

### Report a Bug

1. Please search existing [issues](../../issues) to avoid duplicates.
2. Use the bug template or include:
   - Clear title and description.
   - Steps to reproduce.
   - Expected vs. actual behavior.
   - macOS version, Zig version, how you built the app.
   - Logs if available (see [Testing & QA](#testing--qa)).
3. If you suspect a security issue, skip the tracker and follow [Security Disclosures](#security-disclosures).

### Suggest an Enhancement

1. Check the roadmap in `README.md` and existing [enhancement issues](../../issues?q=label%3Aenhancement).
2. Open a new issue with:
   - Problem you’re trying to solve.
   - Proposed solution or alternatives.
   - Screenshots / sketches if UI changes are involved.
3. Mention why the idea benefits privacy-focused users.

### Improve Docs, Design, or UX

Non-code contributions are hugely valuable:

- Spot a confusing sentence? Open a docs PR or issue.
- Share UX feedback with screenshots or screen recordings.
- Audit copy for clarity or tone.
- Update visuals or icons (attach assets in PR discussions).

### Work on Code

1. Thank you for considering a code contribution - small or large: we welcome it all!
2. Please review app architecture and privacy/security philosophy.
3. Follow the [development workflow](#getting-started-with-development) and keep pull requests focused on a single concern for ease of review and integration.

---

## Getting Started with Development

### Local Setup

- Install dependencies listed in the [README](README.MD), including Zig (matching `build.zig.zon`) and the Xcode Command Line Tools.
- Clone the repo and create a topic branch:  
  `git checkout -b feature/my-improvement`
- Keep changes scoped; small PRs are easier to review quickly.

### Testing & QA

Format and test before pushing:

```bash
# Format any Zig files you altered
zig fmt path/to/file.zig

# Unit tests
zig build test-lib
zig build test-helper
zig build test

# Build the bundle (optional but recommended before release PRs)
zig build -Dtarget=aarch64-macos --release=safe bundle
```

Manual smoke test checklist:

- App launches without errors (`zig build run`).
- File picker accepts images from `~/Downloads`, `~/Documents`, or `~/Desktop`.
- Device list shows removable media and no system disks.
- Flash workflow completes with the helper installed and communication via XPC.
- No memory leaks, segfaults or panics reported buring execution.

Debug logging lives in `~/freetracer.log`. To enable more detail, edit `~/.config/freetracer/preferences.json`:

```json
{
  "debugLevel": 0
}
```

Additional specifics on the architecture and security model live in:

- [Architecture overview](docs/architecture-overview.md)
- [Security & privacy guidance](docs/security-and-privacy.md)

---

## Issues & Discussions

- Use issues for actionable bugs and enhancements.
- Use GitHub Discussions for open-ended questions, ideation, or design explorations.
- Please be respectful, constructive and kind to others when engaging in discussion.
---

## Pull Request Checklist

Before requesting review, please confirm:

- [ ] Branch is rebased on latest `main`.
- [ ] Zig files are formatted (`zig fmt`).
- [ ] `zig build test-lib`, `zig build test-helper`, and `zig build test` all pass.
- [ ] Manual smoke tests completed or listed in the PR.
- [ ] Documentation updated (README, architecture, or security docs as needed).
- [ ] Security and privacy implications documented in the PR body (even if “none”).
- [ ] Screenshots or recordings included for UI changes.

**PR Title Format**

```
[Type] Brief description
# Examples:
# [Fix] Handle large image files gracefully
# [Feature] Add preferences for update checks
# [Docs] Clarify helper installation
```

**PR Description Template**

```
## Summary
What does this PR do? Why is it needed?

## Changes
- Bullet list of notable changes

## Testing
- Commands run or manual QA steps

## Security / Privacy Considerations
- Note any new permissions, data flows, or “none”
```

---

## Reviews & Support

- Maintainers strive to respond quickly. If you haven’t heard back, feel free to nudge the thread.
- Expect collaborative reviews—questions, suggestions, and pairing offers are normal.
- If a PR stalls, we’ll help de-scope or split it so the work can land.

---

## Security Disclosures

Please **do not** report vulnerabilities publicly. Email `product-security@orbitixx.com` with details. We will acknowledge your report and coordinate fixes before disclosure. Thanks!

---

## Additional Resources

- [README](README.MD) — project overview & build instructions
- [Architecture overview](docs/architecture-overview.md)
- [Security & privacy guidance](docs/security-and-privacy.md)
- Governance notes — see the “Contributing” section of [README](README.MD)
- [LICENSE](LICENSE.MD)
- [SECURITY policy](SECURITY.MD)

If anything here is unclear, open a discussion or issue. We’re excited to build Freetracer with you!
