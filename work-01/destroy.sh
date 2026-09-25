#!/usr/bin/env bash
set -euo pipefail

PREFIX="havkin-02"

for i in 1 2; do
  NAME="${PREFIX}-app-${i}"
  if yc compute instance get --name "${NAME}" >/dev/null 2>&1; then
    yc compute instance delete --name "${NAME}"
  else
    echo "Машина ${NAME} не найдена"
  fi
done

if yc vpc subnet get --name "${PREFIX}-subnet" >/dev/null 2>&1; then
  yc vpc subnet delete --name "${PREFIX}-subnet"
else
  echo "Подсеть ${PREFIX}-subnet не найдена"
fi

if yc vpc network get --name "${PREFIX}-net" >/dev/null 2>&1; then
  yc vpc network delete --name "${PREFIX}-net"
else
  echo "Сеть ${PREFIX}-net не найдена"
fi
