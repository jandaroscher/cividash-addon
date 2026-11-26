# Contributing

This add-on follows the contribution guidelines of the CiviDash main
repository: <https://github.com/jandaroscher/cividash/blob/main/CONTRIBUTING.md>.

Open issues and pull requests for the add-on in this repository:
<https://github.com/jandaroscher/cividash-addon>. The openCode copy
(<https://gitlab.opencode.de/regensburg_next/cividash-addon>) is a mirror that is
overwritten from GitHub, so merge requests there cannot be merged. Changes to
the application itself belong in the main repository.

Before opening a pull request, run `helm lint --strict charts/cividash -f
charts/cividash/ci/smoke-values.yaml` and the CIVITAS/CORE policy checks
described in the README under "Versioning and compatibility". CI on GitHub
runs the same checks.

Every commit on `main` and `v2` needs a Developer Certificate of Origin sign-off by a
person, as described in the main repository. On a squash merge, put the
`Signed-off-by` line in the last block of the message, next to the
`Co-authored-by` lines, with no blank line in between. The `DCO` workflow
checks each push to `main` and `v2`.

The repository follows the [REUSE specification](https://reuse.software): new
YAML, shell and template files start with an SPDX header (`reuse annotate
--copyright "JANDA+ROSCHER GmbH & Co. KG" --license EUPL-1.2+ <file>`), files
without comment syntax are covered by `REUSE.toml`. The `REUSE` workflow runs
`reuse lint` on every pull request.
