# Security policy

This repository packages [CiviDash](https://gitlab.opencode.de/regensburg_next/cividash) as a
CIVITAS/CORE add-on (Ansible role + Helm chart). It ships no application code of its
own; the application security policy, supported versions and vulnerability handling
are documented in the
[main repository's `SECURITY.md`](https://gitlab.opencode.de/regensburg_next/cividash/-/blob/main/SECURITY.md).

## Reporting a vulnerability in this add-on

If you find a security issue in the deployment logic here (Ansible tasks, Helm
templates, Keycloak/APISIX wiring), please **do not** open a public GitHub/GitLab
issue. Instead, report it privately:

- Email: `support@janda-roscher.de`

Please include:

- A description of the vulnerability and its potential impact
- Steps to reproduce (proof-of-concept code or requests, if applicable)
- Affected version/commit

### Response times

- We aim to acknowledge new reports within **5 business days**.
- We aim to provide an assessment and response within **30 days** of acknowledgement.
- Confirmed vulnerabilities will be fixed and disclosed in coordination with the
  reporter; timelines depend on severity and complexity.

Please give us reasonable time to investigate and fix an issue before any public
disclosure.
