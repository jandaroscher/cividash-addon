# Contributing

This add-on follows the contribution guidelines of the CiviDash main
repository: <https://github.com/jandaroscher/cividash/blob/main/CONTRIBUTING.md>.

Open issues and pull requests for the add-on in this repository:
<https://github.com/jandaroscher/cividash-addon>. The openCode copy
(<https://gitlab.opencode.de/regensburg_next/cividash-addon>) is a mirror that is
overwritten from GitHub, so merge requests there cannot be merged. Changes to
the application itself belong in the main repository.

Before opening a pull request, run `helm lint chart/cividash`,
`helm template cividash chart/cividash` (see [Helm chart](docs/helm-chart.md))
and `ansible-playbook --syntax-check dev/syntax-check.yml`. CI on GitHub runs
`helm lint` and the Ansible syntax check.
