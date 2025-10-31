# Security & Privacy Guidance

Freetracer puts privacy and least privilege first. This document expands on the abbreviated guidance in `CONTRIBUTING.md` and should be referenced when you build features that touch privileged surfaces.

---

## Core Principles

- **Minimum permissions** — Request only what is required for the user-initiated action.
- **Offline-first** — No unsolicited network traffic; update checks are optional and opt-out friendly.
- **Transparent UX** — Users should know why the app needs a permission or elevated action.
- **Fail secure** — Prefer denying requests on ambiguity or error.

---

## Privileged Helper Rules

When interacting with the helper daemon (`macos-helper`):

1. Do not trust input from the GUI without validation.
2. Verify the GUI’s code signature, bundle ID, and team ID before processing requests.
3. Treat all errors as failure-to-proceed; deny by default.
4. Keep the privileged surface minimal (disk ejection, erase/write).
5. Log security-relevant events without persisting sensitive user data.

Implementation reference: `macos-helper/src/main.zig`, `freetracer-lib/src/macos/Mach.zig`.

---

## Permission Scope

- **File access** — Scoped to `~/Downloads`, `~/Documents`, and `~/Desktop`.
- **Disk access** — Limited to removable media (USB, SD cards). Defensive checks guard against internal disks.
- **Network** — Optional release checks against `github.com`. Users can disable this from preferences.
- **System resources** — Keep to the APIs required for disk arbitration, helper installation, and UI rendering.

Document new permissions in:

1. `macos/Info.plist` usage description.
2. `README.md` (user-facing).
3. `CONTRIBUTING.md` (developer note).

---

## Adding a Security Check

1. Identify the threat (e.g., “malicious helper message”).
2. Implement validation in the closest layer (e.g., `Mach.zig` for XPC messages).
3. Emit structured logs without secrets.
4. Return explicit error codes that callers can act on.
5. Document the guard in code comments and update tests.

---

## Adding a New Permission

1. Justify the requirement in code comments.
2. Update `Info.plist` with a succinct usage description.
3. Update the README and release notes if user-visible.
4. Confirm the permission is the smallest practical scope.
5. Add or update tests/manual QA steps demonstrating correct behavior.

---

## Reporting Security Issues

Please do **not** open public issues for sensitive vulnerabilities. Email `product-security@orbitixx.com` with details. Maintainers acknowledge reports and coordinate fixes privately before disclosure.

---

Questions about hardening or threat models? Open a GitHub Discussion tagged `security` or mention it in your PR and we'll be happy to discuss.
