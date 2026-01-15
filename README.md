# ccbell-sound-packs

Community-curated sound packs for [ccbell](https://github.com/mpolatcan/ccbell) notification plugin.

## Overview

This repository contains sound packs that can be installed via:
```bash
/ccbell:packs install <pack_name>
```

Sound packs are automatically curated from free sound providers (Pixabay, Freesound) via GitHub Actions CI pipeline.

## Available Packs

| Pack | Status | Description |
|------|--------|-------------|
| minimal | Coming soon | Clean, subtle notification sounds |
| classic | Coming soon | Traditional notification tones |
| futuristic | Coming soon | Modern, tech-inspired sounds |

## Directory Structure

```
ccbell-sound-packs/
├── packs/
│   ├── minimal/
│   │   ├── pack.json          # Pack metadata
│   │   └── sounds/
│   │       ├── stop.aiff
│   │       ├── permission_prompt.aiff
│   │       ├── idle_prompt.aiff
│   │       └── subagent.aiff
│   └── ...
├── scripts/
│   └── sound-pack-curator.sh  # Curation script
├── .github/
│   └── workflows/
│       └── curate.yml         # CI pipeline
└── README.md
```

## Creating a New Pack

### Option 1: Manual (Recommended for small packs)

1. Create directory: `packs/my-pack/`
2. Add sounds to `packs/my-pack/sounds/`
3. Create `packs/my-pack/pack.json`:

```json
{
  "id": "my-pack",
  "name": "My Pack",
  "description": "Description of your pack",
  "author": "yourname",
  "version": "1.0.0",
  "events": {
    "stop": "stop.aiff",
    "permission_prompt": "permission.aiff",
    "idle_prompt": "idle.aiff",
    "subagent": "subagent.aiff"
  }
}
```

4. Submit PR

### Option 2: Use Curation Script

```bash
# Query and create pack
./scripts/sound-pack-curator.sh curate pixabay my-pack "notification bell"

# The script will:
# 1. Query Pixabay for sounds
# 2. Download matching sounds
# 3. Convert to AIFF format
# 4. Create pack.json
# 5. Output to packs/my-pack/
```

## Storage Architecture

We store **only pack.json in git** (metadata). Sound files are stored as **GitHub Release assets**.

```
Git Repository (small - only text files)
├── packs/
│   ├── retro/pack.json        # ✅ Metadata only
│   ├── minimal/pack.json
│   └── ...
└── .github/workflows/

GitHub Releases (binary assets)
├── retro-v1.0.0.zip           # ✅ Contains pack.json + sounds/*.aiff
├── minimal-v1.0.0.zip
└── ...
```

### Why?

| Aspect | Solution |
|--------|----------|
| **Repo size** | Stays small (no binary bloat) |
| **Version control** | pack.json changes tracked in git |
| **Fast clone** | Users don't download all sounds |
| **ccbell reads** | From release assets |

### What ccbell Downloads

When user runs `/ccbell:packs install retro`, ccbell:
1. Reads release list from GitHub API
2. Finds retro-v1.0.0.zip asset
3. Downloads and extracts pack.json + sounds

Use Claude Code AI to search and curate sounds based on a theme:

```bash
# Via GitHub Actions UI
1. Go to Actions → "Theme Curation with Claude"
2. Click "Run workflow"
3. Enter theme: "retro", "futuristic", "lofi", "nature", etc.
4. Claude Code will:
   - Search Pixabay for matching sounds
   - Download and convert to AIFF
   - Create pack.json
   - Create GitHub Release with sounds
```

**Or via Issue Comment:**
```markdown
!curate retro
```

Claude will create a PR for the "retro" themed pack!

### Option 2: Simple Scheduled Curation

The `.github/workflows/curate.yml` pipeline:

- **Scheduled**: Runs monthly on the 1st
- **Manual**: Trigger via GitHub Actions UI
- **Auto-publish**: Creates GitHub releases automatically

### Required Secrets

Set in repository settings → Secrets:

| Secret | Provider | Get Key At |
|--------|----------|------------|
| `ANTHROPIC_API_KEY` | Claude Code | [console.anthropic.com](https://console.anthropic.com/) |
| `PIXABAY_API_KEY` | Pixabay | [pixabay.com/api/docs](https://pixabay.com/api/docs/) |
| `FREESOUND_API_KEY` | Freesound | [freesound.org/apiv2/apply](https://freesound.org/apiv2/apply) |
| `GH_TOKEN` | GitHub | Settings → Personal access tokens (repo scope) |

## Usage with ccbell

```bash
# List available packs
/ccbell:packs browse

# Install a pack
/ccbell:packs install minimal

# Use the pack (auto-updates config)
/ccbell:packs use minimal

# Preview before install
/ccbell:packs preview minimal
```

## License

Each sound pack may have different licenses. Check individual `pack.json` files for details.

### Sound Sources

- **Pixabay**: Pixabay License (free for commercial use)
- **Freesound**: Creative Commons (various: CC0, CC-BY, CC-BY-NC)

## Contributing

1. Fork this repository
2. Create a new pack in `packs/your-pack/`
3. Add `pack.json` with metadata
4. Add sounds to `sounds/` subdirectory
5. Submit PR

## For Maintainers

### Manual Curation

```bash
# Run curation manually
gh workflow run curate.yml -f provider=pixabay -f pack_name=minimal -f query="notification bell"
```

### Release a New Pack Version

```bash
# Update pack version in pack.json
# Commit changes
git add packs/minimal/
git commit -m "Update minimal pack v1.1.0"
git push

# CI will automatically create release
```

## Links

- [ccbell Plugin](https://github.com/mpolatcan/ccbell)
- [ccbell-sound-packs Releases](https://github.com/mpolatcan/ccbell-sound-packs/releases)
- [Pixabay Sound Effects](https://pixabay.com/sound-effects/)
- [Freesound](https://freesound.org/)
