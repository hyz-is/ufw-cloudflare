#!/bin/sh

# UFW-Cloudflare v2
# Automatically allow Cloudflare IP addresses through UFW
# Compatible with Ubuntu and Debian-based systems

# System compatibility check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if ! echo "$ID $ID_LIKE" | grep -q -E "ubuntu|debian"; then
        echo "ERROR: This script is only compatible with Ubuntu and Debian-based systems."
        exit 1
    fi
else
    echo "ERROR: Could not determine the operating system. This script is only compatible with Ubuntu and Debian-based systems."
    exit 1
fi

# Check for required dependencies
for cmd in ufw wget awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' is not installed."
        exit 1
    fi
done

cfufw_deleted=0
cfufw_created=0
cfufw_ignored=0
cfufw_nonew=0
cfufw_purge=0
cfufw_showhelp=0
cfufw_supervision=0

# SSH port(s) to always keep open — safety net so enabling UFW never locks you out.
# Space-separated list. Override at runtime, e.g.: CFUFW_SSH_PORTS="22 2233" ./ufw.sh
CFUFW_SSH_PORTS="${CFUFW_SSH_PORTS:-2233}"

cf_ufw_add () {
    if [ ! -z "$1" ] && [ "$1" != "" ]; then
        # Validate IP address format (basic check for IPv4 and IPv6 CIDR)
        if echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$|^([0-9a-fA-F:]+)(/[0-9]{1,3})?$'; then
            rule=$(LC_ALL=C && ufw allow from "$1" to any port 80,443 proto tcp comment "cloudflare" 2>/dev/null)

            if [ "$rule" = 'Rule added' ] || [ "$rule" = 'Rule added (v6)' ]; then
                echo -n "\e[32m+\e[39m"
                cfufw_created=$((cfufw_created+1))
                return
            fi
        fi
    fi

    echo -n "\e[90m.\e[39m"
    cfufw_ignored=$((cfufw_ignored+1))
}

cf_ufw_del () {
    if [ ! -z "$1" ] && [ "$1" != "" ]; then
        # Validate IP address format before attempting deletion
        if echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$|^([0-9a-fA-F:]+)(/[0-9]{1,3})?$'; then
            rule=$(LC_ALL=C && ufw delete allow from "$1" to any port 80,443 proto tcp 2>/dev/null)

            if [ "$rule" = 'Rule deleted' ] || [ "$rule" = 'Rule deleted (v6)' ]; then
                echo -n "\e[31m-\e[39m"
                cfufw_deleted=$((cfufw_deleted+1))
                return
            fi
        fi
    fi

    echo -n "\e[90m.\e[39m"
    cfufw_ignored=$((cfufw_ignored+1))
}

cf_ufw_purge () {
    total="$(ufw status numbered | awk '/# cloudflare$/ {++count} END {print count}')"
    i=1

    if [ -z $total ]; then
        cfufw_deleted=0
        return
    fi

    while [ $i -le $total ]; do
        cfip=$(ufw status numbered | awk '/# cloudflare$/{print $6; exit}')
        cf_ufw_del $cfip
        i=$((i+1))
    done
}

cf_ufw_ssh () {
    for sshport in $CFUFW_SSH_PORTS; do
        if echo "$sshport" | grep -qE '^[0-9]{1,5}$'; then
            rule=$(LC_ALL=C && ufw allow "$sshport"/tcp comment "cf-ufw-ssh" 2>/dev/null)
            case "$rule" in
                *'Skipping adding existing rule'*)
                    echo "SSH ${sshport}/tcp: already allowed." ;;
                *)
                    echo "SSH ${sshport}/tcp: allowed." ;;
            esac
        else
            echo "SSH port '${sshport}' is invalid, skipping."
        fi
    done
}

echo '█░█ █▀▀ █░█░█'
echo '█▄█ █▀░ ▀▄▀▄▀'
echo ''
echo 'Cloudflare UFW Manager v2.0'

for arg in "$@"; do
    case "$arg" in
        '--purge') cfufw_purge=1 ;;
        '-p') cfufw_purge=1 ;;
        '--no-new') cfufw_nonew=1 ;;
        '-n') cfufw_nonew=1 ;;
        '--help') cfufw_showhelp=1 ;;
        '-h') cfufw_showhelp=1 ;;
        '--supervision') cfufw_supervision=1 ;;
        '-s') cfufw_supervision=1 ;;
    esac
done

if [ $cfufw_showhelp -eq 1 ]; then
    echo 'ufw.sh 2.0'
    echo 'Fetches Cloudflare IP ranges and creates UFW allow rules (ports 80 and 443 TCP) for each one.'
    echo 'Always keeps SSH open (default 2233/tcp; override with CFUFW_SSH_PORTS) so enabling UFW never locks you out.'
    echo 'Usage: ./ufw.sh [options]'
    echo 'OPTIONS:'
    echo "\t--help (-h)       : Show this help message."
    echo "\t--purge (-p)      : Remove existing Cloudflare rules (deletes rules with #cloudflare comment)."
    echo "\t--no-new (-n)     : Do not fetch Cloudflare IPs and do not add any new rules to UFW."
    echo "\t--supervision (-s): Enable automatic daily updates via systemd timer."
    echo 'EXAMPLES:'
    echo "\t./ufw.sh --purge"
    echo "\t./ufw.sh --purge --no-new"
    echo "\t./ufw.sh --supervision"
    exit
fi

# Always ensure SSH stays reachable before touching any firewall rules,
# so a fresh setup or the daily timer can never lock you out.
cf_ufw_ssh

if [ $cfufw_purge -eq 1 ]; then
    cf_ufw_purge
fi

if [ $cfufw_nonew -eq 0 ]; then
    [ -e /tmp/cloudflare-ips.txt ] && rm /tmp/cloudflare-ips.txt
    touch /tmp/cloudflare-ips.txt

    wget https://www.cloudflare.com/ips-v4 -q -O ->> /tmp/cloudflare-ips.txt
    echo "" >> /tmp/cloudflare-ips.txt
    wget https://www.cloudflare.com/ips-v6 -q -O ->> /tmp/cloudflare-ips.txt

    # Verify that IP list was fetched successfully
    if [ ! -s /tmp/cloudflare-ips.txt ]; then
        echo ""
        echo "ERROR: Failed to fetch Cloudflare IP ranges. Check your internet connection."
        rm -f /tmp/cloudflare-ips.txt
        exit 1
    fi

    # Process each line, filtering out empty lines and whitespace
    while IFS= read -r cfip || [ -n "$cfip" ]; do
        # Skip empty lines and lines with only whitespace
        if [ -n "$(echo "$cfip" | tr -d '[:space:]')" ]; then
            cf_ufw_add "$(echo "$cfip" | tr -d '[:space:]')"
        fi
    done < /tmp/cloudflare-ips.txt

    [ -e /tmp/cloudflare-ips.txt ] && rm /tmp/cloudflare-ips.txt
fi

echo ''
echo "Rules deleted: ${cfufw_deleted}"
echo "Rules created: ${cfufw_created}"
echo "Rules skipped: ${cfufw_ignored}"
echo 'Done.'

# Ask about supervision activation if not specified as argument
if [ $cfufw_supervision -eq 0 ]; then
    echo ''
    echo -n "Would you like to enable UFW-Cloudflare v2 Supervision (daily auto-update)? (y/n): "
    read answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        cfufw_supervision=1
    fi
fi

# Supervision setup using systemd service + timer
if [ $cfufw_supervision -eq 1 ]; then
    echo ''
    echo "Setting up UFW-Cloudflare v2 Supervision..."

    SCRIPT_PATH="$(readlink -f "$0")"

    # Remove existing supervision units if running as root
    if [ "$(id -u)" -eq 0 ]; then
        if systemctl is-active --quiet ufw-cloudflare-supervision.timer 2>/dev/null; then
            echo "Stopping existing timer..."
            systemctl stop ufw-cloudflare-supervision.timer
        fi

        if systemctl is-active --quiet ufw-cloudflare-supervision.service 2>/dev/null; then
            echo "Stopping existing service..."
            systemctl stop ufw-cloudflare-supervision.service
        fi

        if systemctl is-enabled --quiet ufw-cloudflare-supervision.timer 2>/dev/null; then
            systemctl disable ufw-cloudflare-supervision.timer
        fi

        if systemctl is-enabled --quiet ufw-cloudflare-supervision.service 2>/dev/null; then
            systemctl disable ufw-cloudflare-supervision.service
        fi

        rm -f /etc/systemd/system/ufw-cloudflare-supervision.service
        rm -f /etc/systemd/system/ufw-cloudflare-supervision.timer
        systemctl daemon-reload
    fi

    # Create systemd service unit
    cat > /tmp/ufw-cloudflare-supervision.service << EOF
[Unit]
Description=UFW Cloudflare IP Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} --purge
EOF

    # Create systemd timer unit (runs daily)
    cat > /tmp/ufw-cloudflare-supervision.timer << EOF
[Unit]
Description=UFW Cloudflare IP Update Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Install the units
    if [ "$(id -u)" -eq 0 ]; then
        cp /tmp/ufw-cloudflare-supervision.service /etc/systemd/system/
        cp /tmp/ufw-cloudflare-supervision.timer /etc/systemd/system/
        rm -f /tmp/ufw-cloudflare-supervision.service /tmp/ufw-cloudflare-supervision.timer
        systemctl daemon-reload
        systemctl enable ufw-cloudflare-supervision.timer
        systemctl start ufw-cloudflare-supervision.timer
        echo "Supervision enabled! Cloudflare rules will be updated daily."
        echo "Check timer status: systemctl status ufw-cloudflare-supervision.timer"
    else
        echo "Unit files created in /tmp/"
        echo "To install, run the following commands as root:"
        echo ""
        echo "# Remove existing units (if any)"
        echo "sudo systemctl stop ufw-cloudflare-supervision.timer 2>/dev/null"
        echo "sudo systemctl stop ufw-cloudflare-supervision.service 2>/dev/null"
        echo "sudo systemctl disable ufw-cloudflare-supervision.timer 2>/dev/null"
        echo "sudo rm -f /etc/systemd/system/ufw-cloudflare-supervision.service"
        echo "sudo rm -f /etc/systemd/system/ufw-cloudflare-supervision.timer"
        echo ""
        echo "# Install new units"
        echo "sudo cp /tmp/ufw-cloudflare-supervision.service /etc/systemd/system/"
        echo "sudo cp /tmp/ufw-cloudflare-supervision.timer /etc/systemd/system/"
        echo "sudo systemctl daemon-reload"
        echo "sudo systemctl enable ufw-cloudflare-supervision.timer"
        echo "sudo systemctl start ufw-cloudflare-supervision.timer"
    fi
fi