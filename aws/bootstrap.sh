#!/bin/bash
# ========== ARRANQUE DE UNA EC2 DE BARRIODIGITAL ==========
# Lo ejecuta el UserData de CloudFormation (como root) al crear cada EC2:
#   curl -sSL https://raw.githubusercontent.com/BarrioDigital-2/barriodigital-infra/main/aws/bootstrap.sh | bash -s -- <rol>
#
# Rol: web | apps | mq | kafka
# Antes de llamarlo, el UserData deja las variables del rol en /opt/barriodigital/<rol>.env;
# este script las copia como .env junto al compose correspondiente.
#
# Pasos: swap -> Docker + compose -> clonar repos -> .env -> esperar dependencias -> docker compose up
#
# Variables opcionales (se pasan antes de "bash"):
#   RAMA=develop                      rama a clonar (por defecto main)
#   ESPERAR="10.0.1.5:9092 10.0.1.6:5672"   espera a que esos puertos respondan antes de levantar
set -euo pipefail

ROL="${1:?Uso: bootstrap.sh <web|apps|mq|kafka>}"
RAMA="${RAMA:-main}"                 # rama a clonar de cada repo
ORG="https://github.com/BarrioDigital-2"
BASE=/opt/barriodigital

exec > >(tee -a /var/log/barriodigital-init.log) 2>&1
echo "== Arranque de la EC2 con rol '$ROL' (rama $RAMA)"

# ---------- Qué repos y qué compose usa cada rol ----------
case "$ROL" in
  web)   CARPETA=web;        REPOS="ms-barriodigital-bff barrioDigital-front-angular" ;;
  apps)  CARPETA=apps;       REPOS="ms-barriodigital-requests ms-barriodigital-catalog ms-barriodigital-audit ms-barriodigital-kafka-admin ms-barriodigital-report" ;;
  mq)    CARPETA=mensajeria; REPOS="ms-BarrioDigital-Notifications:ms-barriodigital-notifications ms-barriodigital-rabbit-admin" ;;
  kafka) CARPETA=kafka;      REPOS="" ;;
  *)     echo "Rol desconocido: $ROL"; exit 1 ;;
esac

# ---------- 1. Swap de 2 GB (compilar con Maven/Angular dentro de Docker necesita memoria) ----------
if [ ! -f /swapfile ]; then
  echo "== [1/5] Swap de 2 GB"
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
fi

# ---------- 2. Docker, git, compose y buildx ----------
echo "== [2/5] Docker, git, compose y buildx"
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
     -o /usr/local/lib/docker/cli-plugins/docker-compose
curl -sSL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
     -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/*

# ---------- 3. Clonar barriodigital-infra y los repos del rol ----------
# Formato de cada repo: "nombre-en-github" o "nombre-en-github:carpeta-local"
echo "== [3/5] Repos"
mkdir -p "$BASE" && cd "$BASE"
clonar() {
  local repo="${1%%:*}" carpeta="${1##*:}"
  if [ -d "$carpeta" ]; then
    git -C "$carpeta" pull
  else
    # Si el repo no tiene la rama pedida (ej. rabbit-admin solo tiene main), clona su rama por defecto
    git clone -b "$RAMA" "$ORG/$repo.git" "$carpeta" || git clone "$ORG/$repo.git" "$carpeta"
  fi
}
clonar barriodigital-infra
for r in $REPOS; do clonar "$r"; done

# ---------- 4. Variables del rol ----------
echo "== [4/5] Variables (.env)"
DESTINO="$BASE/barriodigital-infra/aws/$CARPETA"
cp "$BASE/$ROL.env" "$DESTINO/.env"
# Kafka anuncia la IP privada de su propia EC2: se obtiene del servicio de metadatos de AWS (IMDSv2)
if [ "$ROL" = "kafka" ] && ! grep -q '^KAFKA_HOST_IP=' "$DESTINO/.env"; then
  TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  IP_PRIVADA=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
  echo "KAFKA_HOST_IP=$IP_PRIVADA" >> "$DESTINO/.env"
fi
chmod 600 "$DESTINO/.env"

# ---------- Esperar a otras EC2 (ej. apps necesita Kafka y RabbitMQ arriba para crear sus topics) ----------
for destino in ${ESPERAR:-}; do
  host="${destino%%:*}"; puerto="${destino##*:}"
  echo "== Esperando a $host:$puerto"
  until timeout 3 bash -c "</dev/tcp/$host/$puerto" 2>/dev/null; do sleep 10; done
done

# ---------- 5. Levantar ----------
echo "== [5/5] docker compose up ($CARPETA)"
cd "$DESTINO"
docker compose up -d --build
chown -R ec2-user:ec2-user "$BASE"
echo "== EC2 '$ROL' LISTA"
