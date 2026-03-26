# DocRipper — Proxmox LXC Installer

Automated installer for [DocRipper](https://github.com/godspoon/docripper) on Proxmox VE, following the [community-scripts](https://github.com/community-scripts/ProxmoxVE) pattern.

DocRipper rips documentation from any site or GitHub repo into a single Markdown file optimized for LLM context windows. It auto-detects Docusaurus, MkDocs, Sphinx, GitHub Wikis, MS Learn, Zendesk, AWS Docs, Apple DocC, Cloudflare/Astro, and more — with headless Chromium for JS-rendered sites and optional AI quality analysis.

---

## Quick Install

Run this **on your Proxmox host shell** (not inside a container):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/GodSpoon/DocRipper/main/ct/docripper.sh)"
```

This will:
1. Prompt you to confirm default settings (or enter advanced mode)
2. Create a Debian 12 LXC with 2 cores / 1.5 GB RAM / 8 GB disk
3. Install Node.js 20, all Chromium system libraries, and DocRipper
4. Download the Chromium binary via `playwright install`
5. Set up a systemd service that starts on boot
6. Print the access URL when done

---

## Default Container Settings

| Setting | Value |
|---|---|
| OS | Debian 12 (Bookworm) |
| CPU | 2 cores |
| RAM | 1536 MB |
| Disk | 8 GB |
| Network | DHCP |
| Type | Unprivileged (nesting=1) |
| Port | 5000 |

---

## Optional: Anthropic API Key

DocRipper works fully without an API key. The key only enables the AI quality analysis panel that rates each extraction and suggests improvements.

After install, add your key:

```bash
# On Proxmox host — replace 100 with your container ID
pct exec 100 -- nano /opt/docripper/.env
```

Uncomment and fill in:
```
ANTHROPIC_API_KEY=sk-ant-...your-key-here...
```

Then restart:
```bash
pct exec 100 -- systemctl restart docripper
```

Get a free key at [console.anthropic.com](https://console.anthropic.com). DocRipper uses Claude Haiku — very cheap (~$0.001 per analysis).

---

## Updating DocRipper

To pull the latest version, run the installer one-liner again **from inside the container** (not the Proxmox host). The `update_script()` function detects an existing `/opt/docripper` installation and does a `git pull` + rebuild:

```bash
# On Proxmox host — enter the container first
pct enter 100

# Then run the installer — it auto-detects and updates
bash -c "$(curl -fsSL https://raw.githubusercontent.com/GodSpoon/DocRipper/main/ct/docripper.sh)"
```

Or update manually inside the container:

```bash
pct exec 100 -- bash -c "
  cd /opt/docripper && \
  git pull origin main && \
  npm install && \
  npm run build && \
  systemctl restart docripper
"
```

**Convenience commands** (run inside the container or via `pct exec 100 --`):

```bash
# Logs
docripper-log

# Restart / stop / start
docripper-restart
docripper-stop
docripper-start
```

---

## Repository Structure

```
DocRipper/
├── ct/
│   └── docripper.sh          # Proxmox host script (create LXC + orchestrate)
├── install/
│   └── docripper-install.sh  # Runs inside the LXC (install everything)
└── README.md
```

This follows the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) convention exactly. The `ct/` script runs on the Proxmox host and sources shared functions from the community-scripts repo. The `install/` script is pushed into the container and executed there.

---

## Troubleshooting

**Chromium won't launch inside LXC**
The container must be unprivileged with `nesting=1` (set automatically by the installer). If you created the container manually, add it:
```bash
# On Proxmox host
pct set 100 --features nesting=1
pct restart 100
```

**Missing system library error**
On Ubuntu 24.04 LXC templates, some libraries have `t64` suffixes. The installer handles both variants, but if you see errors:
```bash
pct exec 100 -- apt install -y libatk1.0-0t64 libcups2t64 libglib2.0-0t64
```

**Out of memory during Chromium jobs**
Increase container RAM on the Proxmox host:
```bash
pct set 100 --memory 2048
```

**Check service logs**
```bash
pct exec 100 -- journalctl -u docripper -f
# or inside the container:
docripper-log
```
