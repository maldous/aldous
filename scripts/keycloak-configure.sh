#!/usr/bin/env bash
set -euo pipefail
set -x

kubectl exec -i keycloak-0 -- bash <<'EOF'
CONFIG=/tmp/kcadm.config
REALM=aldous
CLIENT_ID=kong
CLIENT_SECRET=kong-secret
/opt/bitnami/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password changeme \
  --config "$CONFIG"
/opt/bitnami/keycloak/bin/kcadm.sh create realms --config "$CONFIG" \
  -s realm="$REALM" \
  -s enabled=true \
  -s registrationAllowed=true \
  -s sslRequired=external \
  -s displayName="$REALM"
/opt/bitnami/keycloak/bin/kcadm.sh create clients -r "$REALM" --config "$CONFIG" \
  -s clientId="$CLIENT_ID" \
  -s "redirectUris=[\"https://aldous.info/callback\"]" \
  -s "webOrigins=[\"https://aldous.info\"]" \
  -s publicClient=false \
  -s protocol=openid-connect \
  -s clientAuthenticatorType=client-secret \
  -s secret="$CLIENT_SECRET" \
  -s 'attributes."access.token.lifespan"=300' \
  -s 'attributes."sso.session.idle.timeout"=1800' \
  -s 'attributes."sso.session.max.lifespan"=36000'
CLIENT_UUID=$(/opt/bitnami/keycloak/bin/kcadm.sh get clients -r "$REALM" --config "$CONFIG" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes | tail -n1)
/opt/bitnami/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r "$REALM" --config "$CONFIG" -f - <<JSON
{
  "name": "email",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-property-mapper",
  "consentRequired": false,
  "config": {
    "userinfo.token.claim": "true",
    "user.attribute": "email",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "claim.name": "email",
    "jsonType.label": "String"
  }
}
JSON
/opt/bitnami/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r "$REALM" --config "$CONFIG" -f - <<JSON
{
  "name": "preferred_username",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-property-mapper",
  "consentRequired": false,
  "config": {
    "userinfo.token.claim": "true",
    "user.attribute": "username",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "claim.name": "preferred_username",
    "jsonType.label": "String"
  }
}
JSON
EOF
