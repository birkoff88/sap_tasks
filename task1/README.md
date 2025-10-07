# SSL/TLS Certificate Expiry Checker

A Python tool for monitoring SSL/TLS certificate expiration dates across multiple domains and ports. Features parallel checking, flexible configuration, and optional webhook alerts.

## Features

- **Flexible Domain Configuration**: Support for standard HTTPS (port 443) and custom ports
- **IDNA/Punycode Support**: Handles internationalized domain names
- **Self-Signed Certificates**: Optional support for internal PKI and self-signed certificates
- **Parallel Execution**: Configurable concurrent checks for faster processing
- **Timezone-Aware**: All calculations use UTC for consistency
- **CI/CD Friendly**: Exit codes suitable for automation and monitoring
- **Webhook Alerts**: Optional notifications to Slack, Teams, or other webhook services
- **Clear Output**: Easy-to-read results with visual indicators (✓, ⚠, ✗)

## Requirements

- Python 3.6+
- `requests` library (optional, only needed for webhook alerts)

## Installation

### Basic Setup

```bash
# Clone or download the script
chmod +x ssl_cert_checker.py

# Install optional dependencies for alerts
pip install requests
```

### Running Locally

```bash
python3 ssl_cert_checker.py
```

### Running with Docker

```bash
# Build the image
docker build -t ssl-cert-checker .

# Run the container
docker run --rm -v $(pwd)/config.json:/app/config.json ssl-cert-checker
```

**Dockerfile example:**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY ssl_cert_checker.py .
COPY config.json .

RUN pip install --no-cache-dir requests

CMD ["python3", "ssl_cert_checker.py"]
```

## Configuration

Create a `config.json` file in the same directory as the script:

```json
{
  "domains": [
    "example.com",
    "google.com",
    {"host": "internal.example.com", "port": 8443}
  ],
  "warning_days": 30,
  "critical_days": 7,
  "timeout": 10,
  "max_workers": 10,
  "allow_invalid": false,
  "fail_on_error": true,
  "alerts": {
    "enabled": false,
    "webhook_url": ""
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `domains` | array | **required** | List of domains to check (strings or objects with `host` and `port`) |
| `warning_days` | integer | 30 | Days before expiry to trigger WARNING status |
| `critical_days` | integer | 7 | Days before expiry to trigger CRITICAL status |
| `timeout` | integer | 10 | Connection timeout in seconds |
| `max_workers` | integer | 10 | Maximum number of parallel checks |
| `allow_invalid` | boolean | false | Allow self-signed or invalid certificates |
| `fail_on_error` | boolean | true | Exit with code 1 if any ERROR status occurs |
| `alerts.enabled` | boolean | false | Enable webhook notifications |
| `alerts.webhook_url` | string | "" | Webhook URL for alerts (Slack, Teams, etc.) |

### Domain Format

Domains can be specified in two ways:

**Simple format** (uses port 443):
```json
"domains": ["example.com", "google.com"]
```

**Extended format** (custom port):
```json
"domains": [
  {"host": "example.com", "port": 443},
  {"host": "internal.example.com", "port": 8443}
]
```

## Output Example

```
======================================================================
 SSL CERTIFICATE EXPIRY CHECK
======================================================================

✓ example.com:443
  Expires: 2025-12-15 (73 days)

⚠ expiring-soon.com:443
  Expires: 2025-10-20 (17 days)

✗ expired.com:443
  Expires: 2025-09-01 (-32 days)

✗ internal.example.com:8443 Error - [Errno 111] Connection refused

======================================================================
 SUMMARY
======================================================================
Total: 4 domains
OK: 1
WARNING: 1
CRITICAL: 0
EXPIRED: 1
ERROR: 1
======================================================================
```

## Exit Codes

| Code | Condition |
|------|-----------|
| 0 | All certificates OK or only WARNING status |
| 1 | Any CRITICAL or EXPIRED status, or ERROR (if `fail_on_error: true`) |

This makes the script suitable for use in CI/CD pipelines and monitoring systems.

## Alerts

When alerts are enabled, the script will send a webhook notification for domains with CRITICAL or EXPIRED status.

### Slack Webhook Example

```json
{
  "alerts": {
    "enabled": true,
    "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  }
}
```

### Microsoft Teams Webhook Example

```json
{
  "alerts": {
    "enabled": true,
    "webhook_url": "https://outlook.office.com/webhook/YOUR-WEBHOOK-URL"
  }
}
```

The alert message format:
```
🚨 Certificate Alert: 2 domain(s) need attention

• expired.com:443 — EXPIRED (-5 days)
• critical.com:443 — CRITICAL (3 days)
```

## Use Cases

### CI/CD Integration

Add to your `.gitlab-ci.yml` or GitHub Actions workflow:

```yaml
# GitHub Actions example
certificate-check:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - name: Check certificates
      run: |
        pip install requests
        python3 ssl_cert_checker.py
```

### Cron Job

Add to your crontab for daily checks:

```bash
# Run daily at 9 AM
0 9 * * * /usr/bin/python3 /path/to/ssl_cert_checker.py
```

### Docker Compose with Scheduling

```yaml
version: '3.8'
services:
  cert-checker:
    image: ssl-cert-checker
    volumes:
      - ./config.json:/app/config.json:ro
    restart: "no"
    # Use with a scheduler like ofelia
```

## Advanced Usage

### Checking Internal/Self-Signed Certificates

Set `allow_invalid: true` in your config to check internal certificates without validation:

```json
{
  "domains": ["internal.corp.com"],
  "allow_invalid": true
}
```

### High-Volume Monitoring

For checking many domains, increase parallelism:

```json
{
  "domains": [...], 
  "max_workers": 50,
  "timeout": 5
}
```

### Custom Thresholds

Adjust warning/critical thresholds based on your renewal process:

```json
{
  "warning_days": 60,
  "critical_days": 14
}
```

## Troubleshooting

### Connection Errors

**Problem**: `Connection refused` or timeout errors

**Solutions**:
- Verify the hostname and port are correct
- Check firewall rules allow outbound connections
- Increase `timeout` value for slow networks
- For IP addresses, SNI is automatically disabled

### Certificate Validation Errors

**Problem**: `certificate verify failed`

**Solutions**:
- For self-signed certificates, set `allow_invalid: true`
- Ensure system CA certificates are up to date
- Check if the certificate chain is complete

### IDNA/Unicode Domain Issues

The script automatically handles internationalized domain names (IDN) by converting them to punycode. No special configuration needed.

## License

This script is provided as-is for monitoring and operations purposes. Modify and distribute freely.

## Contributing

Suggestions and improvements are welcome. Common enhancement ideas:

- JSON output format for programmatic consumption
- Support for additional alert channels (email, PagerDuty, etc.)
- Certificate chain validation details
- Historical tracking and trend analysis
- Support for client certificate authentication

## Support

For issues or questions, consult the inline code documentation or create an issue in your repository.