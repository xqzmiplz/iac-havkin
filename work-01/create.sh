#!/usr/bin/env bash
set -euo pipefail

PREFIX="havkin-02"
ZONE="ru-central1-b"
CIDR="10.12.1.0/24"
DISK_SIZE=20                      # ГБ
PORT=8006                         # порт сервиса
WORD="cloudlab"                   # слово на странице
IMAGE_FAMILY="ubuntu-2204-lts"    # дистрибутив самостоятельной части

SSH_KEY="$HOME/.ssh/id_ed25519.pub"

yc vpc network create --name "${PREFIX}-net"

yc vpc subnet create \
  --name "${PREFIX}-subnet" \
  --network-name "${PREFIX}-net" \
  --zone "${ZONE}" \
  --range "${CIDR}"

for i in 1 2; do
  yc compute instance create \
    --name "${PREFIX}-app-${i}" \
    --hostname "${PREFIX}-app-${i}" \
    --zone "${ZONE}" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="${IMAGE_FAMILY}",type=network-hdd,size="${DISK_SIZE}" \
    --network-interface subnet-name="${PREFIX}-subnet",nat-ip-version=ipv4 \
    --ssh-key "${SSH_KEY}" \
    --labels created-by=cli
done
