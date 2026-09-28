#!/usr/bin/env bash
set -uo pipefail

PREFIX=havkin-02
APP_PORT="${APP_PORT:-8006}"

OVERALL_OK=0

# ---- 1. балансировщик отвечает 200 ----
LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json 2>/dev/null | jq -r '.listeners[0].address // empty')

if [ -z "$LB_IP" ]; then
  echo "✗ балансировщик не найден"
  OVERALL_OK=1
else
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://$LB_IP")
  if [ "$CODE" = "200" ]; then
    echo "✓ балансировщик отвечает: $CODE"
  else
    echo "✗ балансировщик отвечает: $CODE"
    OVERALL_OK=1
  fi
fi

# ---- 2. ответы приходят больше чем с одной машины (и от всех живых машин стенда) ----
if [ -n "$LB_IP" ]; then
  TOTAL_WEB=$(yc compute instance list --format json | jq -r --arg p "$PREFIX-web" '[.[] | select(.name | startswith($p))] | length')

  RESPONDERS=$(for i in $(seq 1 20); do
    curl -s --max-time 3 "http://$LB_IP" | grep -o 'on [a-z0-9-]*' | sed 's/on //'
  done | sort -u)
  COUNT=$(echo "$RESPONDERS" | grep -c .)
  NAMES=$(echo "$RESPONDERS" | tr '\n' ',' | sed 's/,$//')

  if [ "$COUNT" -gt 1 ] && [ "$COUNT" -eq "$TOTAL_WEB" ]; then
    echo "✓ ответили машины: $NAMES"
  elif [ "$COUNT" -gt 1 ]; then
    echo "✗ ответили не все машины ($COUNT из $TOTAL_WEB): $NAMES"
    OVERALL_OK=1
  else
    echo "✗ ответила только одна машина: $NAMES"
    OVERALL_OK=1
  fi
else
  echo "✗ пропускаю проверку машин: балансировщик не найден"
  OVERALL_OK=1
fi

# ---- 3. сервер приложения доступен с веб-сервера по внутреннему адресу ----
WEB1_IP=$(yc compute instance get --name "$PREFIX-web-1" --format json 2>/dev/null \
  | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty')
APP_IP=$(yc compute instance get --name "$PREFIX-app-1" --format json 2>/dev/null \
  | jq -r '.network_interfaces[0].primary_v4_address.address // empty')

if [ -z "$WEB1_IP" ] || [ -z "$APP_IP" ]; then
  echo "✗ сервер приложения недоступен с $PREFIX-web-1 (не найдены адреса)"
  OVERALL_OK=1
else
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 student@"$WEB1_IP" \
      "curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://$APP_IP:$APP_PORT" 2>/dev/null | grep -q "^200$"; then
    echo "✓ сервер приложения доступен с $PREFIX-web-1"
  else
    echo "✗ сервер приложения недоступен с $PREFIX-web-1"
    OVERALL_OK=1
  fi
fi

exit "$OVERALL_OK"
