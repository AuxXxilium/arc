# Security Policy

## Overview

Arc is a customized bootloader for DSM 7.x (Xpenology). As a system-level component that operates during the boot process, security is a critical concern. This document outlines our security policy and procedures for reporting vulnerabilities.

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| Latest release | :white_check_mark: |
| Beta releases | :white_check_mark: |
| Older releases | :x: |

**Note:** We strongly recommend always using the latest stable release to ensure you have the most recent security patches.

## Security Considerations

### System-Level Access
Arc operates as a bootloader with system-level privileges. Users should be aware that:

- Arc has full access to system resources during the boot process
- Any modifications to Arc configuration or code can affect system security
- Only install Arc from official sources (GitHub repositories listed in README)
- Never download Arc from unofficial sources or third parties

### Educational Use Only
As stated in the project README:
- Commercial use is not permitted and strictly forbidden
- The project is released for educational and learning purposes only
- Users assume all responsibility for any modifications or use

### Boot Security
- Secure Boot: Arc may not be compatible with Secure Boot. Disable Secure Boot in your system's BIOS/UEFI if needed
- Physical access: Anyone with physical access to the system can potentially modify the bootloader
- Network exposure: The web interface (port configuration) should not be exposed to untrusted networks

## Reporting a Vulnerability

If you discover a security vulnerability in Arc, please help us protect users by following responsible disclosure practices.

### Where to Report

**Do NOT** open a public GitHub issue for security vulnerabilities.

Instead, please report security issues by:

1. **GitHub Security Advisories** (Preferred):
   - Navigate to the [Security tab](https://github.com/AuxXxilium/arc/security) of this repository
   - Click "Report a vulnerability"
   - Fill out the form with details

2. **Email**:
   - Contact the maintainers directly through GitHub
   - Include "SECURITY" in the subject line

### What to Include

When reporting a vulnerability, please include:

- **Description**: A clear description of the vulnerability
- **Impact**: The potential impact and severity
- **Steps to Reproduce**: Detailed steps to reproduce the issue
- **Proof of Concept**: Code or commands demonstrating the vulnerability (if applicable)
- **Affected Versions**: Which versions of Arc are affected
- **Suggested Fix**: If you have ideas for remediation (optional)

### Response Timeline

- **Initial Response**: We aim to acknowledge your report within 72 hours
- **Status Updates**: We will provide updates on our investigation within 7 days
- **Resolution**: We aim to release a fix within 30 days for critical vulnerabilities

### Disclosure Policy

- We request that you do not publicly disclose the vulnerability until we have released a fix
- We will credit you in the security advisory (unless you prefer to remain anonymous)
- Once a fix is released, we will publish a security advisory with details

## Security Best Practices

When using Arc, follow these security best practices:

### Installation
- Download Arc only from official AuxXxilium GitHub repositories
- Verify the integrity of downloaded files when possible
- Use the guided installation process rather than manual modifications

### Configuration
- Limit access to the Arc web interface to trusted networks only
- Use strong passwords for any authentication mechanisms
- Keep your DSM system updated with the latest security patches
- Regularly update Arc to the latest version

### Custom Modifications
- **Warning**: Custom modifications can compromise system security
- Any user-specific modifications are at your own risk
- Test modifications in a non-production environment first
- Document all changes for troubleshooting purposes

### Network Security
- Do not expose Arc's web interface to the public internet
- Use a firewall to restrict access to trusted IP addresses
- Consider using VPN access for remote management

## Known Security Limitations

Users should be aware of the following limitations:

1. **DSM Security**: Arc is a bootloader for DSM, but DSM security is managed by Synology. Keep DSM updated separately.
2. **Hardware Access**: Physical access to the system can bypass bootloader security.
3. **Educational Project**: This is an educational project without formal security audits.
4. **No Warranty**: As stated in the LICENSE, this software is provided "as is" without warranty of any kind.

## Third-Party Components

Arc integrates various third-party components and code from:
- TTG's original redpill-load project
- pocopico, jumkey, fbelavenuto, wjz304, and other contributors

Security issues in third-party components should be reported to the respective projects as well.

## Updates and Patches

Security updates will be released through:
- GitHub releases with security tags
- Update announcements in release notes
- The Arc project's communication channels

Subscribe to repository releases to be notified of security updates.

## Questions

If you have questions about this security policy, please:
- Open a discussion in the GitHub Discussions section
- Contact the maintainers through GitHub

## Disclaimer

This project is provided for educational purposes only. Users are responsible for:
- Complying with all applicable laws and regulations
- Understanding the security implications of running modified bootloaders
- Any data loss or system damage that may occur

As stated in the project documentation:
> Any user-specific custom modification of the tested & prebuilt bootloader images could potentially cause irreversible data destruction. I'm not responsibly liable for damage or personal loss of any types.
