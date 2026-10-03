#!/usr/bin/env bash
set -euo pipefail

# ---- параметры варианта (умолчания) ----
PREFIX=havkin-02
ZONE_A=ru-central1-b
ZONE_B=ru-central1-d
CIDR_A=10.12.1.0/24
CIDR_B=10.12.2.0/24
APP_PORT_DEFAULT=8006
GREETING_DEFAULT=cloudlab
WEB_COUNT_DEFAULT=3
IMAGE_FAMILY=ubuntu-2404-lts

# ---- порядок: аргумент командной строки > переменная окружения > умолчание ----
WEB_COUNT="${WEB_COUNT:-$WEB_COUNT_DEFAULT}"
APP_PORT="${APP_PORT:-$APP_PORT_DEFAULT}"
GREETING="${GREETING:-$GREETING_DEFAULT}"

while [ $# -gt 0 ]; do
  case "$1" in
    --web-count) WEB_COUNT="$2"; shift 2 ;;
    --port)      APP_PORT="$2"; shift 2 ;;
    --word)      GREETING="$2"; shift 2 ;;
    *) echo "неизвестный аргумент: $1"; exit 1 ;;
  esac
done

echo "параметры: web-count=$WEB_COUNT port=$APP_PORT word=$GREETING"

# ---- вспомогательная функция: создать ресурс, если его ещё нет ----
# использование: ensure "описание для лога" "команда get..." "команда create..."
ensure() {
  local desc="$1" get_cmd="$2" create_cmd="$3"
  if eval "$get_cmd" >/dev/null 2>&1; then
    echo "  $desc уже есть, пропускаю"
  else
    echo "  создаю: $desc"
    eval "$create_cmd"
  fi
}

echo "==> сеть"
ensure "$PREFIX-net" \
  "yc vpc network get --name $PREFIX-net" \
  "yc vpc network create --name $PREFIX-net"

echo "==> подсети"
ensure "$PREFIX-subnet-a" \
  "yc vpc subnet get --name $PREFIX-subnet-a" \
  "yc vpc subnet create --name $PREFIX-subnet-a --network-name $PREFIX-net --zone $ZONE_A --range $CIDR_A"

ensure "$PREFIX-subnet-b" \
  "yc vpc subnet get --name $PREFIX-subnet-b" \
  "yc vpc subnet create --name $PREFIX-subnet-b --network-name $PREFIX-net --zone $ZONE_B --range $CIDR_B"

echo "==> NAT-шлюз и таблица маршрутизации (для закрытой подсети A)"
ensure "$PREFIX-nat" \
  "yc vpc gateway get --name $PREFIX-nat" \
  "yc vpc gateway create --name $PREFIX-nat"

GW_ID=$(yc vpc gateway get --name "$PREFIX-nat" --format json | jq -r .id)

ensure "$PREFIX-rt" \
  "yc vpc route-table get --name $PREFIX-rt" \
  "yc vpc route-table create --name $PREFIX-rt --network-name $PREFIX-net --route destination=0.0.0.0/0,gateway-id=$GW_ID"

# привязка таблицы к подсети A — делаем всегда через update, это безопасно повторять
yc vpc subnet update --name "$PREFIX-subnet-a" --route-table-name "$PREFIX-rt" >/dev/null

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY

# envsubst принимает имена переменных буквально: раскрой мы их заранее,
# подставлять было бы нечего. Одинарные кавычки здесь верны.
# shellcheck disable=SC2016
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < hw-01/cloud-init.tpl.yaml > hw-01/cloud-init.yaml

echo "==> веб-серверы (публичные, распределены по двум зонам)"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  NAME="$PREFIX-web-$i"
  ensure "$NAME" \
    "yc compute instance get --name $NAME" \
    "yc compute instance create \
      --name $NAME \
      --hostname $NAME \
      --zone ${ZONES[$idx]} \
      --platform standard-v3 \
      --cores=2 --core-fraction=20 --memory=2 \
      --preemptible \
      --create-boot-disk image-folder-id=standard-images,image-family=$IMAGE_FAMILY,type=network-hdd,size=10 \
      --network-interface subnet-name=${SUBNETS[$idx]},nat-ip-version=ipv4 \
      --metadata-from-file user-data=hw-01/cloud-init.yaml"
done

echo "==> сервер приложения (зона A, без публичного адреса)"
ensure "$PREFIX-app-1" \
  "yc compute instance get --name $PREFIX-app-1" \
  "yc compute instance create \
    --name $PREFIX-app-1 \
    --hostname $PREFIX-app-1 \
    --zone $ZONE_A \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family=$IMAGE_FAMILY,type=network-hdd,size=10 \
    --network-interface subnet-name=$PREFIX-subnet-a \
    --metadata-from-file user-data=hw-01/cloud-init.yaml"

echo "==> целевая группа"
if yc load-balancer target-group get --name "$PREFIX-tg" >/dev/null 2>&1; then
  echo "  $PREFIX-tg уже есть, пропускаю"
else
  TARGETS=()
  for i in $(seq 1 "$WEB_COUNT"); do
    idx=$(( (i - 1) % 2 ))
    IP=$(yc compute instance get "$PREFIX-web-$i" --format json \
      | jq -r '.network_interfaces[0].primary_v4_address.address')
    TARGETS+=(--target "subnet-name=${SUBNETS[$idx]},address=$IP")
  done


  yc load-balancer target-group create --name "$PREFIX-tg" "${TARGETS[@]}"
fi

echo "==> балансировщик"
if yc load-balancer network-load-balancer get --name "$PREFIX-lb" >/dev/null 2>&1; then
  echo "  $PREFIX-lb уже есть, пропускаю"
else
  TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
  yc load-balancer network-load-balancer create \
    --name "$PREFIX-lb" \
    --region-id ru-central1 \
    --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
    --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/
fi

echo "==> готово: web-count=$WEB_COUNT port=$APP_PORT word=$GREETING"
