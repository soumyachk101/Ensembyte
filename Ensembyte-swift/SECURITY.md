# Ensembyte Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

Please report security vulnerabilities privately — do not open a public issue.

- **GitHub Security Advisory:** Use the "Security" tab on GitHub to privately report a vulnerability
- **Email:** soumya.chk101@gmail.com (security-only, monitored weekly)

We will acknowledge your report within 48 hours and provide a detailed response within 7 days, including a timeline for a fix.

## Security Best Practices for Contributors

- Never commit secrets, tokens, or credentials (even in fixtures or test data)
- All credential handling must go through secure storage mechanisms (e.g., system keychain), never in plaintext
- Network calls must use HTTPS and validate certificates
- All user-supplied input must be sanitized and validated before processing
- Process spawning and command execution must sanitize all inputs

## Dependency Security

We monitor dependencies for known vulnerabilities via CI. See `.github/workflows/` for the audit pipeline.
