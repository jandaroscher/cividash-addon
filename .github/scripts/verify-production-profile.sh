#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025-2026 JANDA+ROSCHER GmbH & Co. KG
#
# SPDX-License-Identifier: EUPL-1.2+

# Renders the add-on the way a production installation does and checks it
# against the CIVITAS/CORE 2 base and production policies.
#
# CORE's verify-addon.sh only replaces the components list of its test
# environments, so global.profile stays "development" and the production
# values (replicas, PodDisruptionBudgets) are never rendered. This script
# sets profile: production and the S3 storage settings an operator sets.
#
# Usage: verify-production-profile.sh <core-checkout> [addon-path]

set -euo pipefail

CORE_ROOT=$(cd "$1" && pwd)
ADDON_PATH=$(cd "${2:-$PWD}" && pwd)
ADDON_ID=$(yq -r '.component' "$ADDON_PATH/civitas-component.yaml")

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

git -C "$CORE_ROOT" archive HEAD | tar -x -C "$WORKDIR"
cp -r "$WORKDIR/defaults/deployment" "$WORKDIR/deployment"
mkdir -p "$WORKDIR/deployment/addons"
cp -r "$ADDON_PATH" "$WORKDIR/deployment/addons/$ADDON_ID"

ENV_DIR="$WORKDIR/deployment/environments/production"
{
  echo "global:"
  echo "  profile: production"
  echo "components:"
  yq -r '.components[] | "  - " + .' "$WORKDIR/defaults/environment/global.yaml"
  echo "  - $ADDON_ID"
} > "$ENV_DIR/global.yaml.gotmpl"
cat > "$ENV_DIR/$ADDON_ID.yaml.gotmpl" <<'VALUES'
cividash:
  cividash:
    storage: s3
    s3:
      existingSecret: cividash-s3
      endpoint: https://s3.example.org
      bucket: cividash-media
      publicUrl: https://s3.example.org/cividash-media
VALUES

cd "$WORKDIR"
rendered="$WORKDIR/rendered.yaml"
helmfile template -f deployment/helmfile.yaml --skip-tests -e production \
  --selector "component=$ADDON_ID" > "$rendered"

# An empty render would pass every policy.
count=$(yq ea '[select(.kind != null)] | length' "$rendered")
if [[ $count -eq 0 ]]; then
  echo "Rendered no resources for $ADDON_ID" >&2
  exit 1
fi
echo "Rendered $count resources for $ADDON_ID with profile production"

# Warnings fail too: require-minimum-replicas only warns, but with profile
# production every Deployment outside policy-exceptions.yaml must meet it.
kyverno apply .ci/policies/base .ci/policies/production --resource "$rendered" \
  --exception "deployment/addons/$ADDON_ID/policy-exceptions.yaml" --warn-exit-code 1
