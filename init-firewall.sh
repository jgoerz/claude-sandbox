#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Verify required commands are available
MISSING=()
for cmd in iptables iptables-save ipset curl jq dig ip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Error: required commands not found:"
  for cmd in "${MISSING[@]}"; do
    echo "  - $cmd"
  done
  exit 1
fi

# Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
for key in hooks web api git packages pages importer actions dependabot copilot; do
    ranges=$(echo "$gh_ranges" | jq -r ".${key}[]?" 2>/dev/null || true)
    if [ -n "$ranges" ]; then
        for cidr in $ranges; do
            ipset add allowed-domains "$cidr" 2>/dev/null || true
        done
    fi
done

# Fetch Fastly CDN IPs (serves rubygems.org gem downloads)
echo "Fetching Fastly CDN IP ranges (rubygems.org)..."
fastly_ranges=$(curl -s https://api.fastly.com/public-ip-list | jq -r '.addresses[]?' 2>/dev/null || true)
if [ -n "$fastly_ranges" ]; then
    for cidr in $fastly_ranges; do
        ipset add allowed-domains "$cidr" 2>/dev/null || true
    done
fi

# Resolve and add other allowed domains
for domain in \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "gitlab.com" \
    "registry.gitlab.com" \
    "rubygems.org" \
    "index.rubygems.org"; do
    echo "Resolving $domain..."
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
    if [ -n "$ips" ]; then
        for ip in $ips; do
            ipset add allowed-domains "$ip/32" 2>/dev/null || true
        done
    fi
done

# Detect host network and allow it (for port forwarding to work)
HOST_IP=$(ip route | grep default | cut -d" " -f3)
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections and allowed domains only
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configured successfully."

# Verification
echo "Testing connectivity..."
if curl -sf --max-time 5 https://api.github.com > /dev/null 2>&1; then
    echo "  [PASS] api.github.com is reachable"
else
    echo "  [WARN] api.github.com is not reachable"
fi
if curl -sf --max-time 5 https://gitlab.com > /dev/null 2>&1; then
    echo "  [PASS] gitlab.com is reachable"
else
    echo "  [WARN] gitlab.com is not reachable"
fi
if curl -sf --max-time 5 https://rubygems.org > /dev/null 2>&1; then
    echo "  [PASS] rubygems.org is reachable"
else
    echo "  [WARN] rubygems.org is not reachable"
fi
if curl -sf --max-time 5 https://example.com > /dev/null 2>&1; then
    echo "  [FAIL] example.com should be blocked but is reachable"
else
    echo "  [PASS] example.com is blocked"
fi
