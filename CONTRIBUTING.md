# Contributing

This add-on follows the contribution guidelines of the CiviDash main
repository: <https://gitlab.opencode.de/regensburg_next/cividash/-/blob/main/CONTRIBUTING.md>.

Open issues and merge requests for the add-on in this repository:
<https://gitlab.opencode.de/regensburg_next/cividash-addon>. Changes to the
application itself belong in the main repository.

Before opening a merge request, run `helm lint chart/cividash`,
`helm template cividash chart/cividash` (see [Helm chart](docs/helm-chart.md))
and `ansible-playbook --syntax-check dev/syntax-check.yml`. The GitHub mirror
runs `helm lint` and the Ansible syntax check in CI; openCode has no pipeline
for this repository, so run both locally before opening a merge request.
