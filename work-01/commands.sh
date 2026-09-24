export PREFIX=havkin-02    # подставьте свой префикс
export ZONE=ru-central1-b     # ваша зона из варианта
export CIDR=10.12.1.0/24      # ваша подсеть из варианта
export DISK_SIZE=20          # размер диска из варианта, ГБ

yc vpc network create --name "$PREFIX-net"

yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"

yc vpc subnet list

yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

yc compute instance list

yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'    # проверка количества выключенных машинexport PREFIX=havkin-02    # подставьте свой префикс
export ZONE=ru-central1-b     # ваша зона из варианта
export CIDR=10.12.1.0/24      # ваша подсеть из варианта
export DISK_SIZE=20          # размер диска из варианта, ГБ

yc vpc network create --name "$PREFIX-net"

yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"

yc vpc subnet list

yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

yc compute instance list

yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'    # проверка количества выключенных машин
