#!/usr/bin/env bash
# Consulta a capacidade ARM (A1.Flex) na Oracle sem criar nada.
# Env: OCI_USER OCI_FP OCI_TENANCY OCI_REGION OCI_KEY (caminho da chave privada)
# Opcionais: OCPUS (padrão 1) MEM_GB (padrão 6) NTFY_TOPIC
set -euo pipefail
KEYID="${OCI_TENANCY}/${OCI_USER}/${OCI_FP}"

oci_call() { # serviço método caminho [corpo]
  local HOST="$1.${OCI_REGION}.oraclecloud.com" method=$2 path=$3 body=${4:-} date hdrs sig
  date=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S GMT")
  if [ "$method" = POST ]; then
    local sha len; sha=$(printf '%s' "$body" | openssl dgst -sha256 -binary | openssl base64 -A)
    len=$(printf '%s' "$body" | wc -c | tr -d ' ')
    local s="(request-target): post $path
host: $HOST
date: $date
x-content-sha256: $sha
content-type: application/json
content-length: $len"
    sig=$(printf '%s' "$s" | openssl dgst -sha256 -sign "$OCI_KEY" | openssl base64 -A)
    curl -sS -X POST "https://$HOST$path" -H "date: $date" -H "x-content-sha256: $sha" \
      -H "content-type: application/json" -H "content-length: $len" --data "$body" \
      -H "Authorization: Signature version=\"1\",keyId=\"$KEYID\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date x-content-sha256 content-type content-length\",signature=\"$sig\""
  else
    local s="(request-target): get $path
host: $HOST
date: $date"
    sig=$(printf '%s' "$s" | openssl dgst -sha256 -sign "$OCI_KEY" | openssl base64 -A)
    curl -sS "https://$HOST$path" -H "date: $date" \
      -H "Authorization: Signature version=\"1\",keyId=\"$KEYID\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date\",signature=\"$sig\""
  fi
}

ENC_T=$(printf '%s' "$OCI_TENANCY" | sed 's/:/%3A/g')
ADS=$(oci_call identity GET "/20160918/availabilityDomains?compartmentId=$ENC_T")
AD=$(printf '%s' "$ADS" | grep -o '"name" *: *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)
[ -n "$AD" ] || { echo "Falha ao obter AD: $ADS" >&2; exit 2; }

BODY=$(printf '{"compartmentId":"%s","availabilityDomain":"%s","shapeAvailabilities":[{"instanceShape":"VM.Standard.A1.Flex","instanceShapeConfig":{"ocpus":%s,"memoryInGBs":%s}}]}' \
  "$OCI_TENANCY" "$AD" "${OCPUS:-1}" "${MEM_GB:-6}")
OUT=$(oci_call iaas POST /20160918/computeCapacityReports "$BODY")
echo "$OUT"
STATUS=$(printf '%s' "$OUT" | grep -o '"availabilityStatus" *: *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)
echo "AD=$AD status=${STATUS:-?}"
if [ "$STATUS" = AVAILABLE ]; then
  echo "VAGA=1"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "vaga=1" >> "$GITHUB_OUTPUT"
fi
