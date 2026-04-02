# 🔥 SharePoint Online Library Sync & Migration Validation

> **A field guide for comparing, diffing, and copying files between SharePoint Online document libraries — without losing your mind or trusting Microsoft's migration tools.**

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [Tools Evaluated](#-tools-evaluated)
- [The Answer: rclone](#-the-answer-rclone)
- [Installation](#-installation)
- [Configuring SharePoint Remotes](#-configuring-sharepoint-remotes)
- [Essential Commands](#-essential-commands)
- [RcloneView GUI](#-rcloneview-gui)
- [SharePoint Gotchas](#-sharepoint-gotchas)
- [Custom Graph API Scripts (Alternative Approach)](#-custom-graph-api-scripts-alternative-approach)
- [Entra App Registration Notes](#-entra-app-registration-notes)
- [Quick Reference Card](#-quick-reference-card)

---

## 🧩 The Problem

You've migrated a SharePoint document library from one site to another. File counts don't match. Some files didn't make it. Microsoft's own migration tools aren't fixing the gap.

You need a reliable way to:

1. **Compare** two SharePoint document libraries
2. **Identify** exactly which files are missing
3. **Copy** only the missing files to the destination

---

## 🪦 Tools Evaluated

| Tool | Verdict | Notes |
|:---|:---|:---|
| **SharePoint Migration Tool (SPMT)** | ❌ | Designed for on-prem/file-share → SPO, not SPO → SPO |
| **Migration Manager** | ❌ | Wrapper around SPMT, same limitations |
| **Mover** (in SP Admin Center) | ⚠️ | Supports cloud-to-cloud, but heavy setup for small gaps |
| **ShareGate** | ⚠️ | Excellent but licensed per seat — overkill for cleanup |
| **Custom PowerShell + Graph API** | ⚠️ | Works, but slow and painful to maintain |
| **rclone** | ✅ | Free, fast, battle-tested, SharePoint-native via Graph API |

> **💡 Before writing custom scripts, check whether a mature tool already solves the problem.**

---

## 🏆 The Answer: rclone

[rclone](https://rclone.org/) is an open-source command-line tool for managing files on cloud storage. It supports **70+ backends** including SharePoint Online via the Microsoft Graph API. Think of it as **robocopy for the cloud**.

**What it does well:**

- Recursive enumeration of SharePoint libraries
- File comparison by path, size, and hash
- Incremental copy (only transfers what's missing)
- Chunked uploads for large files
- Automatic retry on throttling (429s)
- Parallel transfers
- Progress reporting

**Limitations:**

- No server-side copy between SharePoint sites (data routes through your machine)
- Uploads are stamped with the current user and timestamp, not the original author/dates

---

## 💾 Installation

```powershell
# Windows
winget install Rclone.Rclone

# macOS
brew install rclone

# Linux
sudo apt install rclone   # or curl https://rclone.org/install.sh | sudo bash

# Verify
rclone version
```

Restart your shell after install so the PATH update takes effect.

---

## 🔧 Configuring SharePoint Remotes

Each SharePoint site/library needs its own named remote. You'll create one for the source and one for the destination.

### Step-by-Step

```powershell
rclone config
```

| Prompt | Value |
|:---|:---|
| `n/s/q` | `n` (new remote) |
| `name` | Descriptive name, e.g. `sp-source` |
| `Storage` | `onedrive` (Microsoft OneDrive — covers SharePoint too) |
| `client_id` | *blank* — rclone has a built-in app registration |
| `client_secret` | *blank* |
| `region` | `global` — unless your tenant is GCC/GCC-High |
| `tenant` | *blank* — auto-detected from your browser sign-in |
| `Edit advanced config?` | `n` |
| `Use web browser to authenticate?` | `y` |
| **→ Browser opens, sign in with your M365 account** | |
| `config_type` | `search` (Search for a SharePoint site) |
| `config_search_term` | Your site name |
| `config_site` | Pick the correct site from search results |
| `config_driveid` | Pick `Documents (documentLibrary)` |
| `Keep this remote?` | `y` |

Repeat for the destination (e.g. `sp-dest`).

### Verify

```powershell
# List configured remotes
rclone listremotes

# Browse source library
rclone lsd sp-source: --max-depth 1

# Browse destination library
rclone lsd sp-dest: --max-depth 1
```

### Security Notes on Authentication

- rclone uses **delegated permissions** via OAuth2 browser sign-in — it acts as *you*, not as an app with its own access
- Tokens are stored in `rclone.conf` (default: `~/.config/rclone/rclone.conf` on Linux, `%APPDATA%\rclone\rclone.conf` on Windows)
- **Protect this file.** It contains refresh tokens that grant access to your SharePoint libraries. Treat it like a credential.
- Consider encrypting the config: `rclone config --set-password`
- If your tenant enforces Conditional Access policies, rclone's built-in app registration may be blocked — you can register your own Entra app and pass `--onedrive-client-id` and `--onedrive-client-secret`

---

## ⚡ Essential Commands

> **Always include `-P` for progress reporting.** Without it, rclone appears to hang on large libraries.

### Check: Find What's Missing

```powershell
rclone check "sp-source:SourceFolder" "sp-dest:" \
    --missing-on-dst missing-files.txt \
    --one-way -P
```

- `--one-way` — only checks source → dest (ignores extras on dest)
- `--missing-on-dst` — writes missing file paths to a text file
- Ignore the `sizes differ` / `quickxor differ` errors in the console — see [Gotchas](#-sharepoint-gotchas)

### Copy: Push Missing Files Only

```powershell
rclone copy "sp-source:SourceFolder" "sp-dest:" --ignore-existing -P
```

| Flag | Purpose |
|:---|:---|
| `--ignore-existing` | **Critical.** Skips files already on dest. Without this, rclone re-copies everything due to hash mismatches. |
| `-P` | Real-time progress |
| `--dry-run` | Preview without transferring |

### Targeted Copy: Specific Subfolder

```powershell
rclone copy "sp-source:SourceFolder/Subfolder" "sp-dest:Subfolder" --ignore-existing -P
```

### Sync: Make Destination Match Source Exactly

```powershell
# ⚠️ DESTRUCTIVE — deletes files from dest that aren't in source
rclone sync "sp-source:SourceFolder" "sp-dest:" -P
```

> 🛑 **Only use `sync` if you are certain** no one has added files directly to the destination. Prefer `copy --ignore-existing` for migration cleanup.

### File Count

```powershell
rclone size "sp-source:SourceFolder" -P
rclone size "sp-dest:" -P
```

---

## 🖥️ RcloneView GUI

[RcloneView](https://rcloneview.com/) is a free desktop GUI for rclone (Windows/Mac/Linux).

### Setup

1. Download from https://rcloneview.com/src/download
2. Install and open
3. Your CLI-configured remotes appear automatically — no extra setup

The **free tier** covers browsing, file transfers, folder comparison, and real-time monitoring. Paid tiers add scheduling and advanced filtering — not needed for migration cleanup.

### GUI Safety

| Right-Click Option | What It Does | Safe? |
|:---|:---|:---|
| **Copy** | Copies to destination, doesn't delete extras | ✅ |
| **Sync** | Makes dest match source, **deletes extras from dest** | ⚠️ |

> The GUI Copy may not include `--ignore-existing` by default. For large libraries where hash mismatches trigger re-copies, use the terminal instead.

---

## 💣 SharePoint Gotchas

### Hash Mismatches Are Normal — Not Corruption

SharePoint rewrites Office documents (`.docx`, `.xlsx`, `.pptx`) on upload. It modifies internal XML, recompresses content, and updates metadata. This means:

- **QuickXorHash** values differ between source and dest even when content is identical
- **File sizes** may differ slightly
- `rclone check` reports these as errors — they are **false positives**

In real-world testing, a 36,000-file library produced **11,186 hash/size mismatches** but only **25 genuinely missing files**. Don't panic at the error count.

### `--ignore-existing` Is Non-Negotiable for Copy

Without it, rclone sees the hash mismatches and re-transfers files that already exist on the destination. For a multi-GB library, this wastes hours.

### Token Storage Security

- `rclone.conf` contains OAuth refresh tokens — treat it as a sensitive credential
- Set a config password: `rclone config --set-password`
- On shared machines, restrict file permissions on `rclone.conf`
- Tokens are scoped to the signing-in user's permissions — rclone cannot access sites the user doesn't have access to

### No Server-Side Copy

Data flows: `Source SPO → your machine → Dest SPO`. Transfer speed is limited by your local connection and SharePoint's per-session throttling (~3-5 MB/s per stream).

### Path Length Limits

SharePoint enforces a **400-character limit** on the full path including filename. Deep nesting + long filenames can cause copy failures.

### Conditional Access / Tenant Restrictions

If your tenant blocks third-party app registrations or enforces strict Conditional Access:

1. Register your own Entra app (see below)
2. Grant delegated `Sites.Read.All` (for check) and `Sites.ReadWrite.All` (for copy)
3. Pass your app's credentials: `rclone config` → enter your `client_id` and `client_secret` when prompted
4. Add `http://localhost:53682/` as a redirect URI on the app registration

---

## 📜 Custom Graph API Scripts (Alternative Approach)

If rclone is not an option (policy restrictions, air-gapped environments), you can build the same workflow with PowerShell and the Microsoft Graph API directly.

### Requirements

- PowerShell 7.4+
- Entra app registration with delegated `Sites.Read.All` (read) or `Sites.ReadWrite.All` (write)
- Authorization code flow with PKCE (works with Security Defaults enabled)
- `http://localhost:8400` as a redirect URI

### Architecture

```
Browser sign-in → Auth code + PKCE → Access token
    → Graph API: /sites/{host}:/{sitePath}     (resolve site)
    → Graph API: /sites/{id}/drives             (find Documents library)
    → Graph API: /drives/{id}/root:/path:/children?$top=200  (enumerate)
    → Recurse folders, collect file paths
    → Diff by relative path (case-insensitive)
    → For copy: GET download URL → PUT to dest (< 4MB) or upload session (≥ 4MB)
```

### Key Lessons from Building This

| Issue | Resolution |
|:---|:---|
| PnP.PowerShell v3 list view threshold bug | Abandon PnP, use Graph API directly |
| Device code flow blocked by Security Defaults | Use auth code + PKCE instead |
| `$Host` is a reserved PowerShell variable | Use a different variable name |
| SharePoint views vs. folders | `"FolderName/All Documents"` fails — `"All Documents"` is a view, not a folder |
| `Set-StrictMode` breaks `$item.folder` checks | Use `$null -ne $item.folder` instead of `$item.folder` |
| Spaces in folder names | Encode each path segment individually with `[uri]::EscapeDataString()` |
| Download URLs expire within minutes | Re-fetch the item by ID immediately before downloading |
| Access tokens expire in ~60 minutes | Add refresh token handling for long-running operations |
| Runtime: ~45 minutes for 36K files | rclone does the same work in ~20 minutes with parallelization |

> **Bottom line:** The custom approach works but is slower, harder to maintain, and solves a problem rclone already solved. Use it only if you can't use rclone.

---

## 🔐 Entra App Registration Notes

### Using rclone's Built-In App

rclone ships with a multi-tenant app registration. No Entra setup needed. Permissions requested at sign-in:

- `Files.Read`, `Files.Read.All`, `Files.ReadWrite`, `Files.ReadWrite.All`
- `Sites.Read.All`

### Registering Your Own App

If your tenant blocks rclone's built-in app or you want tighter permission scoping:

1. Go to **Entra ID → App registrations → New registration**
2. Name it descriptively (e.g. `rclone-migration`)
3. Set redirect URI: `http://localhost:53682/` (Web or Mobile/Desktop)
4. Under **API permissions**, add Microsoft Graph delegated permissions:
   - `Sites.Read.All` (for check/compare)
   - `Sites.ReadWrite.All` (for copy)
5. **Grant admin consent** if required by your tenant
6. Under **Authentication**, enable **Allow public client flows**
7. Note the **Application (client) ID**
8. When running `rclone config`, enter your `client_id` at the prompt

> ⚠️ **Never commit client secrets, tokens, or `rclone.conf` to version control.** Add `rclone.conf` and any token files to `.gitignore`.

---

## 🃏 Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│                   SHAREPOINT SYNC CHEAT SHEET                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FIND WHAT'S MISSING                                            │
│  rclone check "src:folder" "dest:" \                            │
│      --missing-on-dst missing.txt --one-way -P                  │
│                                                                 │
│  COPY MISSING FILES ONLY                                        │
│  rclone copy "src:folder" "dest:" --ignore-existing -P          │
│                                                                 │
│  DRY RUN FIRST                                                  │
│  rclone copy "src:folder" "dest:" --ignore-existing -P --dry-run│
│                                                                 │
│  FILE COUNT                                                     │
│  rclone size "remote:path" -P                                   │
│                                                                 │
│  BROWSE                                                         │
│  rclone lsd "remote:path" --max-depth 1                         │
│                                                                 │
│  ENCRYPT YOUR CONFIG                                            │
│  rclone config --set-password                                   │
│                                                                 │
│  ⚠️  ALWAYS use -P | ALWAYS use --ignore-existing with copy     │
│  🛑 NEVER use sync unless you intend to delete from dest        │
│  🔒 NEVER commit rclone.conf to version control                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

*Tested against SharePoint Online (Microsoft 365 E3/F3) with rclone v1.73.3 on Windows 11 — April 2026.*
