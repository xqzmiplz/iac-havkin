#!/usr/bin/env bash
set -euo pipefail

PREFIX=havkin-02

echo "==> балансировщик и целевая группа"
if yc load-balancer network-load-balancer get --name "$PREFIX-lb" >/dev/null 2>&1; then
  yc load-balancer network-load-balancer delete --name "$PREFIX-lb"
else
  echo "балансировщик $PREFIX-lb не найден"
fi

if yc load-balancer target-group get --name "$PREFIX-tg" >/dev/null 2>&1; then
  yc load-balancer target-group delete --name "$PREFIX-tg"
else
  echo "целевая группа $PREFIX-tg не найдена"
fi

echo "==> машины "
INSTANCES=$(yc compute instance list --format json | jq -r --arg p "$PREFIX" '.[] | select(.name | startswith($p)) | .name')
if [ -n "$INSTANCES" ]; then
  echo "$INSTANCES" | while read -r name; do
    yc compute instance delete --name "$name"
    echo "удалена машина: $name"
  done
else
  echo "машин с префиксом $PREFIX не найдено"
fi

echo "==> дополнительный диск"
if yc compute disk get --name "$PREFIX-data" >/dev/null 2>&1; then
  yc compute disk delete --name "$PREFIX-data"
else
  echo "диск $PREFIX-data не найден"
fi

echo "==> подсети"
for subnet in "$PREFIX-subnet-a" "$PREFIX-subnet-b"; do
  if yc vpc subnet get --name "$subnet" >/dev/null 2>&1; then
    yc vpc subnet delete --name "$subnet"
  else
    echo "подсеть $subnet не найдена"
  fi
done

echo "==> сеть"
if yc vpc network get --name "$PREFIX-net" >/dev/null 2>&1; then
  yc vpc network delete --name "$PREFIX-net"
else
  echo "сеть $PREFIX-net не найдена"
fi

echo "==> готово, стенд снесён"
