#!/usr/bin/env bash
# =============================================================================
# Local kind smoke for the cividash-addon.
#
# Spins up a throwaway kind cluster, loads the locally-built cividash-app/cividash-web
# images, deploys the add-on data-plane (MariaDB StatefulSet + fpm/web/queue/
# scheduler + migrate Job) via the REAL role tasks, and pulls NGSI-LD data from
# the local bare Stellio broker on the host (docker/civitas/v1.6.2 stack, :8090).
#
# Keycloak/APISIX/Ingress are skipped (they need a full CORE control plane);
# this proves the own-DB approach + the manifests work in a real cluster.
#
# Prereqs: kind, kubectl, ansible (+ `kubernetes` python lib), docker;
#          images cividash-app:dev + cividash-web:dev built; Stellio reachable on :8090.
#
# Usage:   dev/run-smoke.sh           # deploy + verify
#          dev/run-smoke.sh teardown  # delete the kind cluster
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER="cividash-smoke"
CTX="kind-${CLUSTER}"
NS="cividash-smoke"
APP_IMG="ghcr.io/jandaroscher/cividash-app:dev"
WEB_IMG="ghcr.io/jandaroscher/cividash-web:dev"

if [[ "${1:-}" == "teardown" ]]; then
  kind delete cluster --name "$CLUSTER"
  exit 0
fi

# ansible's bundled python holds the `kubernetes` lib; localhost would otherwise
# auto-discover a different interpreter without it.
ANSIBLE_PY="$(ansible --version | grep -oE '/[^ )]+/bin/python[0-9.]*' | head -1 || true)"
echo "ansible python: ${ANSIBLE_PY:-<auto>}"

# 1) cluster
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER"
fi

# 2) images -> tag to the refs the manifests resolve, load into kind
docker image inspect cividash-app:dev >/dev/null
docker image inspect cividash-web:dev >/dev/null
docker tag cividash-app:dev "$APP_IMG"
docker tag cividash-web:dev "$WEB_IMG"
kind load docker-image "$APP_IMG" "$WEB_IMG" --name "$CLUSTER"

# 3) host address reachable from pods (kind network IPv4 gateway) -> Stellio :8090
GW="$(docker network inspect kind -f '{{range .IPAM.Config}}{{println .Gateway}}{{end}}' | grep -E '^[0-9]+\.' | head -1)"
echo "kind gateway (host from pods): $GW"

# 4) deploy via the real role tasks (secrets -> db -> migrate -> workloads)
ansible-playbook "$HERE/smoke-playbook.yml" \
  -e "civitas_gateway_ip=$GW" \
  ${ANSIBLE_PY:+-e "ansible_python_interpreter=$ANSIBLE_PY"}

# 5) verify
echo "== pods =="
kubectl --context "$CTX" -n "$NS" get pods -o wide
kubectl --context "$CTX" -n "$NS" rollout status deploy/cividash-fpm --timeout=180s
kubectl --context "$CTX" -n "$NS" rollout status deploy/cividash-web --timeout=180s

POD="$(kubectl --context "$CTX" -n "$NS" get pod -l app.kubernetes.io/name=cividash-fpm -o jsonpath='{.items[0].metadata.name}')"

echo "== tenant backfill =="
kubectl --context "$CTX" -n "$NS" exec "$POD" -- php artisan tenancy:backfill

# The migrate Job seeds IntegrationSettings.api_url from CIVITAS_API_URL, which
# the add-on sets to the CORE path /context/ngsi-ld. NgsiLdClient prefers the
# DB-stored setting over config/env, so point that setting at the LOCAL bare
# Stellio broker (which serves /ngsi-ld/v1) for the smoke.
SYNC_URL="http://$GW:8090/ngsi-ld/v1"
echo "== point IntegrationSettings.api_url at the local broker =="
kubectl --context "$CTX" -n "$NS" exec "$POD" -- env SMOKE_URL="$SYNC_URL" \
  php artisan tinker --execute='$s=app(\App\Settings\IntegrationSettings::class); $s->api_url=getenv("SMOKE_URL"); $s->save(); echo "api_url=".$s->api_url;'
for phase in "--dry-run" "" ""; do
  echo "== sync ${phase:-(real/re-run)} =="
  kubectl --context "$CTX" -n "$NS" exec "$POD" -- php artisan integration:sync-civitas --tenant=default $phase
done

echo "== /up via cividash-web =="
kubectl --context "$CTX" -n "$NS" port-forward svc/cividash-web 18080:80 >/dev/null 2>&1 &
PF=$!; sleep 4
# Capture the HTTP status (and tolerate transport errors -> empty CODE) WITHOUT
# aborting the script yet, so the port-forward is always cleaned up below.
CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/up || true)"
echo "/up -> ${CODE:-<no response>}"
# Always tear down the background port-forward before deciding pass/fail, so a
# failed probe never leaks the kubectl port-forward process.
kill "$PF" 2>/dev/null || true
if [[ "$CODE" != "200" ]]; then
  echo "FAIL: /up did not return 200 (got '${CODE:-<no response>}')" >&2
  exit 1
fi

echo "== persisted rows =="
kubectl --context "$CTX" -n "$NS" exec cividash-db-0 -- \
  sh -c 'mariadb -ucividash -p"$MARIADB_PASSWORD" cividash -N -e "select concat(\"tiles=\", count(*)) from tiles; select concat(\"metric_values=\", count(*)) from metric_values;"' 2>/dev/null || true

echo "DONE"
