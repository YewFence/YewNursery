# Developer Guide for Agents (AGENTS.md)

This document provides guidelines for AI agents and developers working on the `YewNursery` Scoop bucket.
This repository contains manifests for installing Windows applications via Scoop.

## 1. Environment & Context
- **Platform:** Windows is the primary target.
- **Shell:**
  - Agents should use `bash` for their own operations (e.g., git, listing files).
  - Project scripts in `bin/` are PowerShell (`.ps1`) and should be executed via `bash` (e.g., `powershell -File bin/test.ps1` or simply `.\bin\test.ps1` if supported by the shell tool).
  - **Note:** `SCOOP_HOME` environment variable is required by scripts. If not set, they attempt to resolve it via `scoop prefix scoop`.

## 2. Build & Test Commands

### Running Tests
- **Run all tests:**
  ```powershell
  .\bin\test.ps1
  ```
  This runs the Pester test suite (`Scoop-Bucket.Tests.ps1`) which validates JSON schemas, hashes, and URLs.
  It is the primary CI gate. Ensure this passes before submitting changes.

- **Validate a specific app manifest:**
  There is no direct single-file test command, but you can verify specific aspects:
  ```powershell
  # Check version updates (simulates update check)
  # This verifies that checkver regex matches and autoupdate URLs are valid
  .\bin\checkver.ps1 -App <app-name>

  # Check URLs and Hashes
  # Verifies that download links are accessible and hashes match
  .\bin\checkurls.ps1
  .\bin\checkhashes.ps1
  ```

### Linting & Formatting
- **Format JSON manifests:**
  ```powershell
  .\bin\formatjson.ps1
  ```
  **Critical:** Run this before committing any changes to `.json` files in the `bucket/` directory. It enforces indentation (4 spaces) and key sorting.

- **Find missing checkver:**
  ```powershell
  .\bin\missing-checkver.ps1
  ```
  Helps identify apps that are missing auto-update configurations.

## 3. Code Style & Conventions

### App Manifests (`bucket/*.json`)
- **Format:** Standard JSON (strict). Avoid comments in `.json` files; use `.jsonc` only if strictly necessary and supported (but standard apps are `.json`).
- **Indentation:** 4 spaces (enforced by `formatjson.ps1`).
- **Naming:** Kebab-case filenames (e.g., `app-name.json`). Matches the application name (case-insensitive in usage, but file system is case-preserving).

### Manifest Fields
- **Required Fields:**
  - `version`: Current version string.
  - `description`: Concise description (English preferred unless app is region-specific).
  - `homepage`: Official website or GitHub repo.
  - `license`: SPDX identifier (e.g., "MIT", "Apache-2.0").
  - `url` / `architecture`: Download links.
  - `hash`: SHA256 checksum.
  - `checkver`: Auto-update configuration (Crucial for maintenance).
  - `autoupdate`: URL templates for future updates.

- **Optional Fields:**
  - `bin`: Executables to shim.
  - `shortcuts`: Start menu shortcuts `["exe", "Label"]`.
  - `persist`: Config files to keep across updates.
  - `pre_install` / `post_install`: PowerShell scripts for setup.

- **Reference:** See `bucket/app-name.template.jsonc` for a comprehensive field reference.

### PowerShell Scripts
- Use Pester for testing logic.
- Follow PowerShell best practices (Verb-Noun naming, proper parameters).
- Scripts in `bin/` are utilities for maintaining the bucket.

### Python (If applicable)
- Use `uv` for package management.
- Follow PEP 8.

## 4. Git & Commit Guidelines

### Commit Messages
- **Language:** **Chinese (中文)**.
- **Format:** Conventional Commits.
  - `feat: ...` for new apps or features.
  - `fix: ...` for bug fixes or manifest corrections.
  - `chore: ...` for maintenance (e.g., refactoring scripts).
- **Examples:**
  - `feat: 新增应用 vscode`
  - `fix: 修复 ripgrep 下载链接失效的问题`
  - `app: 更新 google-chrome 至版本 120.0.6099.110` (automated style)
  - `chore: 优化 checkver 脚本性能`

### Pull Requests
- Use `bin/auto-pr.ps1` logic as a reference for creating PRs if automating.
- Ensure `checkver` works before submitting.
- One app per Pull Request is preferred for clarity.

## 5. Agent Behavior Rules

### General
- **Tone:** Professional, direct, no chit-chat.
- **Language:** Respond in Chinese (as requested by user preference in other context) or English as appropriate for the task (Manifests are usually English). *Self-correction: User preference dictates Chinese interaction.*

### Safety & Integrity
- **Verify Hashes:** Always calculate SHA256 hashes (`scoop hash <file>`) or verify against official vendor checksums. Never guess hashes.
- **Non-Destructive:** Do not delete `persist` data unless explicitly asked.

### Tools & Operations
- **Search First:** Use `grep` and `glob` to find existing manifests before creating new ones.
- **Paths:** Always use absolute paths in tool calls.
- **Docker:** Use `docker compose` (no hyphen).
- **Network:** Use `fetch` tools to verify URLs if `checkurls.ps1` fails.

## 6. Common Issues & Troubleshooting

- **Hash Mismatch:**
  - Check if the vendor replaced the binary silently.
  - Check if `architecture` (32bit vs 64bit) is correct.
- **Download Failed:**
  - Check if User-Agent headers are required (use `#/headers` in URL).
  - Check if the URL is a direct link or requires a redirect/cookie.
- **Update Failure:**
  - Verify `checkver` regex at https://regex101.com.
  - Ensure `autoupdate` placeholders (`$version`, `$match1`) are correct.

## 7. Useful Resources
- [Scoop App Manifest Documentation](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Scoop Checkver Documentation](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests#checkver)
