#!/usr/bin/env bash
set -euo pipefail

PREFIX=havkin-02

echo "==> балансировщик и целевая группа"
if yc load-balancer network-load-balancer get --name "$PREFIX-lb" >/dev/null 2>&1; then
  yc load-balancer network-load-balancer delete --name "$PREFIX-lb"
else
  echo "  $PREFIX-lb не найден, пропускаю"
fi

if yc load-balancer target-group get --name "$PREFIX-tg" >/dev/null 2>&1; then
  yc load-balancer target-group delete --name "$PREFIX-tg"
else
  echo "  $PREFIX-tg не найдена, пропускаю"
fi

echo "==> машины (по префиксу)"
INSTANCES=$(yc compute instance list --format json | jq -r --arg p "$PREFIX" '.[] | select(.name | startswith($p)) | .name')
if [ -n "$INSTANCES" ]; then
  echo "$INSTANCES" | while read -r name; do
    yc compute instance delete --name "$name"
    echo "  удалена машина: $name"
  done
else
  echo "  машин с префиксом $PREFIX не найдено, пропускаю"
fi

echo "==> отвязка таблицы маршрутизации от подсети A (обязательно до удаления таблицы)"
if yc vpc subnet get --name "$PREFIX-subnet-a" >/dev/null 2>&1; then
  yc vpc subnet update --name "$PREFIX-subnet-a" --route-table-name "" >/dev/null 2>&1 || true
fi

echo "==> таблица маршрутизации и NAT-шлюз"
if yc vpc route-table get --name "$PREFIX-rt" >/dev/null 2>&1; then
  yc vpc route-table delete --name "$PREFIX-rt"
else
  echo "  $PREFIX-rt не найдена, пропускаю"
fi

if yc vpc gateway get --name "$PREFIX-nat" >/dev/null 2>&1; then
  yc vpc gateway delete --name "$PREFIX-nat"
else
  echo "  $PREFIX-nat не найден, пропускаю"
fi

echo "==> подсети"
for subnet in "$PREFIX-subnet-a" "$PREFIX-subnet-b"; do
  if yc vpc subnet get --name "$subnet" >/dev/null 2>&1; then
    yc vpc subnet delete --name "$subnet"
  else
    echo "  $subnet не найдена, пропускаю"
  fi
done

echo "==> сеть"
if yc vpc network get --name "$PREFIX-net" >/dev/null 2>&1; then
  yc vpc network delete --name "$PREFIX-net"
else
  echo "  $PREFIX-net не найдена, пропускаю"
fi

echo "==> готово, стенд снесён"
echo "проверьте отдельно: yc compute disk list, yc vpc address list"
