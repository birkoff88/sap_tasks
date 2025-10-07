#!/usr/bin/env python3
"""
SSL/TLS Certificate Expiry Checker

Features:
- Domains from config (supports strings or {"host": "...", "port": 8443})
- IDNA (punycode) host handling
- Optional allow_invalid (for self-signed / internal PKI)
- Timezone-aware UTC calculations
- Parallel checks (configurable max_workers)
- Clear summary + CI-friendly exit codes
- Optional webhook alerts (Slack/Teams/etc.)
"""

import ssl
import socket
import json
import sys
import ipaddress
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib.parse import urlparse
from email.utils import parsedate_to_datetime  # robust certificate date parser


# --------------------------- Config & helpers ---------------------------

def load_config(config_file='config.json'):
    """Load and validate configuration from JSON file"""
    try:
        with open(config_file, 'r') as f:
            cfg = json.load(f)
    except Exception as e:
        print(f"Error loading config: {e}")
        sys.exit(1)

    # Required
    domains = cfg.get('domains', [])
    if not isinstance(domains, list) or not domains:
        print("Config error: 'domains' must be a non-empty list")
        sys.exit(1)

    # Thresholds
    warning_days = int(cfg.get('warning_days', 30))
    critical_days = int(cfg.get('critical_days', 7))
    if warning_days < critical_days or critical_days < 0:
        print("Config error: require warning_days >= critical_days >= 0")
        sys.exit(1)

    # Defaults / optional
    cfg.setdefault('timeout', 10)                 # seconds
    cfg.setdefault('max_workers', 10)             # parallelism
    cfg.setdefault('allow_invalid', False)        # allow self-signed/internal
    cfg.setdefault('fail_on_error', True)         # exit non-zero if any ERROR
    cfg.setdefault('alerts', {"enabled": False, "webhook_url": ""})

    return cfg


def clean_hostname(domain_or_host: str) -> str:
    """Normalize a domain/host string and return IDNA-encoded hostname (no port)."""
    host = urlparse(f'https://{domain_or_host}').netloc or domain_or_host
    host = host.split(':')[0]
    try:
        return host.encode('idna').decode('ascii')
    except Exception:
        return host  # fallback (should rarely happen)


def sni_name_for(hostname: str):
    """Return SNI server_hostname, or None for literal IP addresses."""
    try:
        ipaddress.ip_address(hostname)
        return None  # don't send SNI for IPs
    except ValueError:
        return hostname


def iter_domains(domains):
    """
    Yield (display_name, host, port) for each domain entry.
    Supports:
      - "example.com"
      - {"host": "example.com", "port": 8443}
    """
    for entry in domains:
        if isinstance(entry, dict):
            host = entry.get('host')
            port = int(entry.get('port', 443))
            if not host:
                continue
            yield f"{host}", host, port
        else:
            host = str(entry)
            yield host, host, 443


# --------------------------- Core logic ---------------------------

def get_cert_expiry(domain: str, port: int = 443, timeout: int = 10, allow_invalid: bool = False):
    """
    Get certificate expiration datetime (tz-aware UTC) for host:port.
    Returns datetime or None on error.
    """
    hostname = clean_hostname(domain)
    try:
        context = ssl.create_default_context()
        if allow_invalid:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE

        with socket.create_connection((hostname, port), timeout=timeout) as sock:
            with context.wrap_socket(sock, server_hostname=sni_name_for(hostname)) as ssock:
                cert = ssock.getpeercert()
                not_after = cert.get('notAfter')
                if not not_after:
                    raise ValueError("Certificate missing 'notAfter'")

                # Robust, tz-aware parse; normalize to UTC
                expiry_dt = parsedate_to_datetime(not_after).astimezone(timezone.utc)
                return expiry_dt

    except Exception as e:
        print(f"✗ {domain}:{port} Error - {e}")
        return None


def determine_status(days_left: int, warning_days: int, critical_days: int):
    if days_left < 0:
        return 'EXPIRED', '✗'
    if days_left <= critical_days:
        return 'CRITICAL', '✗'
    if days_left <= warning_days:
        return 'WARNING', '⚠'
    return 'OK', '✓'


def check_one(host: str, port: int, warning_days: int, critical_days: int, timeout: int, allow_invalid: bool):
    expiry_date = get_cert_expiry(host, port=port, timeout=timeout, allow_invalid=allow_invalid)
    now = datetime.now(timezone.utc)

    if expiry_date is None:
        return {
            'domain': host, 'port': port, 'status': 'ERROR', 'days': -999, 'expiry': None
        }

    days_left = (expiry_date - now).days
    status, symbol = determine_status(days_left, warning_days, critical_days)

    print(f"{symbol} {host}:{port}")
    print(f"  Expires: {expiry_date.date().isoformat()} ({days_left} days)\n")

    return {
        'domain': host,
        'port': port,
        'status': status,
        'days': days_left,
        'expiry': expiry_date.isoformat()
    }


def check_certificates(domains, warning_days=30, critical_days=7, timeout=10, max_workers=10, allow_invalid=False):
    """Check all certificates (in parallel) and return results list."""
    print("\n" + "=" * 70)
    print(" SSL CERTIFICATE EXPIRY CHECK")
    print("=" * 70 + "\n")

    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = []
        for display, host, port in iter_domains(domains):
            futures.append(
                ex.submit(check_one, host, port, warning_days, critical_days, timeout, allow_invalid)
            )
        for fut in as_completed(futures):
            results.append(fut.result())

    return results


def print_summary(results):
    """Print summary statistics."""
    print("=" * 70)
    print(" SUMMARY")
    print("=" * 70)

    status_counts = {'OK': 0, 'WARNING': 0, 'CRITICAL': 0, 'EXPIRED': 0, 'ERROR': 0}
    for r in results:
        status_counts[r['status']] += 1

    print(f"Total: {len(results)} domains")
    for status, count in status_counts.items():
        if count > 0:
            print(f"{status}: {count}")
    print("=" * 70 + "\n")


def send_alert(results, config):
    """Send alerts via webhook if configured."""
    alerts = config.get('alerts', {}) or {}
    critical_results = [r for r in results if r['status'] in ['CRITICAL', 'EXPIRED']]
    if not critical_results or not alerts.get('enabled'):
        return

    webhook_url = alerts.get('webhook_url')
    if not webhook_url:
        return

    try:
        import requests
        message = f" Certificate Alert: {len(critical_results)} domain(s) need attention\n\n"
        for r in critical_results:
            message += f"• {r['domain']}:{r.get('port', 443)} — {r['status']} ({r['days']} days)\n"

        resp = requests.post(webhook_url, json={"text": message}, timeout=8)
        if 200 <= resp.status_code < 300:
            print("Alert sent!")
        else:
            print(f"Alert failed: HTTP {resp.status_code} {resp.text[:120]}")
    except Exception as e:
        print(f"Could not send alert: {e} (is 'requests' installed in your environment?)")


def main():
    cfg = load_config()
    results = check_certificates(
        cfg['domains'],
        warning_days=int(cfg.get('warning_days', 30)),
        critical_days=int(cfg.get('critical_days', 7)),
        timeout=int(cfg.get('timeout', 10)),
        max_workers=int(cfg.get('max_workers', 10)),
        allow_invalid=bool(cfg.get('allow_invalid', False)),
    )

    print_summary(results)
    send_alert(results, cfg)

    # Exit code policy
    has_critical = any(r['status'] in ['CRITICAL', 'EXPIRED'] for r in results)
    has_error = any(r['status'] == 'ERROR' for r in results)
    fail_on_error = bool(cfg.get('fail_on_error', True))
    exit_bad = has_critical or (fail_on_error and has_error)
    sys.exit(1 if exit_bad else 0)


if __name__ == '__main__':
    main()
