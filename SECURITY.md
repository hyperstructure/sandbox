# Security policy

Please report vulnerabilities privately through GitHub's **Security → Report a
vulnerability** on this repository, not in a public issue. We acknowledge
reports within three working days.

In fctl, the sandbox is the security boundary: each session runs in a VM or
container of its own, and inside it the `agent` user has sudo without a
password. What fctl puts into a sandbox, and how it handles credentials and
billing, is in [fctl's security docs](https://fctl.sh/docs/security/).
