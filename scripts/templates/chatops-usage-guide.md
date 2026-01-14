### ChatOps Available

Use these commands in PR comments to update the manifest automatically:

| Command | Usage | Description |
|---------|-------|-------------|
| `/set-bin` | `/set-bin "app.exe"` | Set the main executable. (Appends if exists) |
| `/set-shortcut` | `/set-shortcut "App Name"`<br>`/set-shortcut "app.exe" "App Name"` | Create a Start Menu shortcut (Auto-detect target or manual). (Appends if exists) |
| `/set-persist` | `/set-persist "config.ini"` | Persist configuration files. (Appends if exists) |
| `/set-key` | `/set-key "description" "New desc"` | Update any manifest field manually. |
| `/clean` | `/clean "shortcuts"` | Remove a field from the manifest. |
| `/list-config` | `/list-config` | Show current configuration status. |
| `/help` | `/help` | Show this usage guide. |
