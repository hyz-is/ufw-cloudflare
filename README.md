# UFW-Cloudflare

🌐 **English** | [Português](README.pt-BR.md) | [Español](README.es.md) | [中文](README.zh.md) | [Íslenska](README.is.md)

Automatically manage [Cloudflare IP ranges](https://www.cloudflare.com/ips/) in UFW (Uncomplicated Firewall). This script fetches the latest Cloudflare IPv4 and IPv6 addresses and creates firewall allow rules for HTTP/HTTPS traffic (ports 80 and 443 TCP), ensuring only Cloudflare-proxied requests reach your origin server.

Designed for **Ubuntu servers** (also compatible with Debian-based systems).

> **DDoS Prevention:** By allowing only Cloudflare IP ranges and blocking all other direct traffic to ports 80/443, your origin server becomes invisible to attackers. All HTTP/HTTPS requests must pass through Cloudflare's network first, leveraging its built-in DDoS mitigation, WAF, and bot protection before reaching your server. Direct-to-origin DDoS attacks are effectively blocked since non-Cloudflare IPs are denied at the firewall level.

## Why?

When your domain is proxied through Cloudflare, all visitor traffic arrives from [Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) instead of individual visitor IPs. Your firewall must allow these ranges, otherwise legitimate traffic gets blocked. Without this configuration, your origin server IP may be exposed and vulnerable to direct DDoS attacks that bypass Cloudflare entirely. This script automates that process and keeps the rules up to date.

## Requirements

- **Ubuntu 20.04+** (or Debian-based system)
- `ufw` installed and enabled
- `wget`
- Root privileges (`sudo`)

## Quick Start

```bash
wget -O ufw.sh https://raw.githubusercontent.com/hyzis-manager/ufw-cloudflare/main/ufw.sh
chmod +x ufw.sh
sudo ./ufw.sh
```

On first run, the script will:

1. Ensure **SSH stays allowed** (port **2233/tcp** by default) — lockout protection when enabling the firewall
2. Fetch the current Cloudflare IPv4 and IPv6 ranges from `cloudflare.com/ips-v4` and `cloudflare.com/ips-v6`
3. Create UFW allow rules for each range on ports **80** and **443** (TCP)
4. Ask if you want to enable **Supervision** (automatic daily updates)

## Usage

```
sudo ./ufw.sh [options]
```

| Option | Short | Description |
|---|---|---|
| `--help` | `-h` | Show help message |
| `--purge` | `-p` | Remove all existing Cloudflare rules (tagged with `#cloudflare` comment) before adding new ones |
| `--no-new` | `-n` | Do not fetch IPs or add new rules (use with `--purge` to only remove rules) |
| `--supervision` | `-s` | Enable automatic daily updates via systemd timer |

## Examples

**First-time setup** — fetch and allow all Cloudflare IPs:

```bash
sudo ./ufw.sh
```

**Refresh rules** — remove outdated rules and add current ones:

```bash
sudo ./ufw.sh --purge
```

**Remove all Cloudflare rules** without adding new ones:

```bash
sudo ./ufw.sh --purge --no-new
```

**Enable daily auto-update** (Supervision):

```bash
sudo ./ufw.sh --supervision
```

## SSH Port (default)

Every time it runs — including the automatic **Supervision** updates — the script ensures **SSH stays allowed**, so you can never lock yourself out when enabling/tightening the firewall. By default it allows port **2233/tcp** from anywhere, tagged with the `cf-ufw-ssh` comment.

This rule is **independent of the Cloudflare rules**: `--purge` (which only removes rules tagged `# cloudflare`) does **not** delete it.

To use different port(s), set the `CFUFW_SSH_PORTS` variable (space-separated list):

```bash
# Standard SSH port (22) instead of the custom one
sudo CFUFW_SSH_PORTS="22" ./ufw.sh

# Keep both during a port migration
sudo CFUFW_SSH_PORTS="22 2233" ./ufw.sh
```

## Supervision

The Supervision feature installs a **systemd timer** that runs the script once every 24 hours with `--purge`, ensuring your firewall rules always reflect the latest Cloudflare IP ranges.

When enabled, two systemd units are created:

- `ufw-cloudflare-supervision.service` — oneshot service that executes the script
- `ufw-cloudflare-supervision.timer` — timer that triggers the service daily (and 5 minutes after boot)

### Managing the timer

```bash
# Check timer status
systemctl status ufw-cloudflare-supervision.timer

# View next scheduled run
systemctl list-timers ufw-cloudflare-supervision.timer

# Disable auto-updates
sudo systemctl stop ufw-cloudflare-supervision.timer
sudo systemctl disable ufw-cloudflare-supervision.timer

# Manually trigger an update
sudo systemctl start ufw-cloudflare-supervision.service
```

## How It Works

1. Ensures the SSH rule first: `ufw allow 2233/tcp comment "cf-ufw-ssh"` (always, even with `--purge` or `--no-new`)
2. Fetches IPv4 ranges from `https://www.cloudflare.com/ips-v4`
3. Fetches IPv6 ranges from `https://www.cloudflare.com/ips-v6`
4. For each CIDR range, runs: `ufw allow from <IP> to any port 80,443 proto tcp comment "cloudflare"`
5. When `--purge` is used, removes all existing UFW rules tagged with the `# cloudflare` comment before adding fresh ones (the SSH rule `cf-ufw-ssh` is preserved)
6. Validates IP formats and verifies the fetch was successful before applying changes

## Output Legend

During execution, the script displays progress indicators:

- **`+`** (green) — rule created
- **`-`** (red) — rule deleted
- **`.`** (gray) — rule skipped (already exists or invalid)

## Cloudflare IP Ranges

The script fetches IPs directly from Cloudflare's official endpoints. These ranges are also available via the [Cloudflare API](https://developers.cloudflare.com/api/resources/ips/methods/list/) at `https://api.cloudflare.com/client/v4/ips` (no authentication required). Cloudflare updates these ranges infrequently but recommends keeping your allowlist current.

## License

MIT
