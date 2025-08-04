#!/usr/bin/env bash

KC_REALM=aldous
KC_USER=admin
KC_PASS=changeme
KC_CLIENT=kong
KC_SECRET=kong-secret
KC_URL=https://auth.aldous.info

curl -s -k -X POST "$KC_URL/realms/$KC_REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$KC_CLIENT" \
  -d "client_secret=$KC_SECRET" \
  -d "username=$KC_USER" \
  -d "password=$KC_PASS" \
  -d "grant_type=password" \
  -d "scope=openid profile email" \
| jq -r '.access_token'
