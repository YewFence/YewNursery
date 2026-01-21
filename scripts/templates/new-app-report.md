## Automatic App Manifest Generation

**Repository**: [{{Owner}}/{{Repo}}]({{Homepage}})
**Version**: {{Version}}
**License**: {{License}}
**Description**: {{Description}}

### Detection Status

| Field | Status | Value |
|-------|--------|-------|
| `version` | ✅ Detected | {{Version}} |
| `architecture` | ✅ Detected | 64bit |
| `hash` | ✅ Calculated | {{Hash}} |
| `bin` | {{BinStatus}} | {{BinValue}} |
| `shortcuts` | {{ShortcutStatus}} | |
| `checkver` | ✅ Configured | `github` |

### File Structure Analysis

```text
{{FileTree}}
```

**Candidates found**:
{{CandidatesStr}}

### Scoop Manifest Fields Guide

- **`bin`**: (Important) The executable that will be shimmed. This allows you to run the app directly from the command line (e.g., `app`). If missing, you won't be able to run it easily. 
> If the executable filename contains the version, use `pre_install` to rename it to a stable name and point `bin` to the stable name so Excavator updates do not break it.   
> FYI: 
> ```
> "pre_install": "Rename-Item \"$dir\\app-v$version-windows-amd64.exe\" 'app.exe'"
> "bin": "app.exe"
> ```
- **`shortcuts`**: (Optional) Creates entries in the Windows Start Menu. Useful for GUI applications. Format: `["exe", "Shortcut Name"]`.
- **`persist`**: (Optional) Directories or files that should be preserved during updates (e.g., configuration files, databases). Vital for keeping user data safe.
- **`checkver`**: (Automated) Configured to check GitHub releases for updates.

{{ChatOpsGuide}}
