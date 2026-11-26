---
name: delete-comment
description: Audit and remove code comments by categorizing each into Tautology, Excuse, Stale, or Decision Record, filing issues for excuses, moving decisions into docs/adr/, and updating the ratcheted SwiftLint baseline. Use when auditing comments, clearing comment-lint violations, or invoking /delete-comment.
---

# Delete Comment

Audit code comments in the target scope (or the whole repository) and eliminate them according to the four-category policy.

## Scope

Default to files with `no_comments` violations (`swiftlint lint --strict` or `.swiftlint.baseline.json`), or any paths the user specifies. Always skip tool directives (`// swift-tools-version:`, `// swiftlint:`, `// swiftformat:`, `// eslint-`, `#!`).

## Categories and Actions

Classify every comment block with surrounding code context:

| Category | Definition | Action |
| --- | --- | --- |
| **Tautology** | Repeats what is already visible from the code (including `// MARK:` dividers, obvious docstrings, section headers). | Delete the comment. |
| **Stale** | References outdated code, versions, frameworks, commented-out code, or boilerplate Xcode file headers. | Delete the comment. |
| **Excuse** | Justifies a hack, workaround, `TODO`/`FIXME`, fragile sleep/retry, duplicated logic, or tech debt instead of fixing it. | Delete the comment and file a GitHub issue describing the hack and the proper fix. |
| **Decision Record** | Documents a non-obvious architectural, protocol, privacy, performance, or platform invariant that a future change could accidentally break. | Move the rationale into the matching ADR under `docs/adr/` (or create the next numbered `docs/adr/NNNN-<topic>.md` and link it in `docs/adr/README.md`), then delete the comment. |

## Workflow

1. **Inventory**: Scan target files (or extract `no_comments` entries from `.swiftlint.baseline.json` / `swiftlint lint`) to list every comment block with surrounding context.
2. **Classify**: Assign each block to `Tautology`, `Stale`, `Excuse`, or `Decision Record` (leaving only compiler/linter directives intact).
3. **File Excuses**: Open one focused issue per distinct hack/workaround (group closely related excuses in the same file when they represent one root cause).
4. **Update ADRs**: Record every `Decision Record` in `docs/adr/` with file paths (no volatile line numbers), what the invariant is, and why it exists.
5. **Delete comments**: Remove all non-directive comments cleanly (trimming leftover trailing whitespace and collapsing double blank lines). If `App/helio-everywhere/src/` changed, rebuild `App/helio-everywhere/dist/`.
6. **Ratchet the lint baseline**:
   ```bash
   swiftformat .
   swiftlint lint --write-baseline .swiftlint.baseline.json
   swiftlint lint --strict
   ```
   The baseline must never gain `no_comments` entries—only shrink toward zero.
7. **Verify**: Build the package and run unit tests before committing. Report counts by category, issues filed, ADRs updated, and lines of code shed.
