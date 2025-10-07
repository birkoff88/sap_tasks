#!/bin/bash
# ------------------------------- user-data.sh --------------------------------
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

# Vars from Terraform (all strings; numbers converted in TF)
efs_id="${efs_id}"
efs_dns="${efs_dns}"
mount_dir="${mount_dir}"
app_port="${app_port}"
db_secret_arn="${db_secret_arn}"
db_host="${db_host}"
db_port="${db_port}"
db_name="${db_name}"
aws_region="${aws_region}"
alb_dns="${alb_dns}"
GITEA_VERSION="${GITEA_VERSION}"

# Packages (AL2023/AL2 compatible)
PKG="dnf"; command -v dnf >/dev/null 2>&1 || PKG="yum"
$PKG -y update
$PKG -y install amazon-efs-utils jq git wget tar || true
command -v psql >/dev/null 2>&1 || $PKG -y install postgresql15 || $PKG -y install postgresql || true
command -v aws  >/dev/null 2>&1 || $PKG -y install awscli || true   # ensure aws CLI exists

# Region via IMDSv2 fallback
if [ -z "${aws_region}" ] || [ "${aws_region}" = "null" ]; then
  token="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"
  aws_region="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/region)"
fi

# Mount EFS with TLS (idempotent)
mkdir -p "${mount_dir}"
if ! grep -q "^${efs_dns}:" /etc/fstab; then
  echo "${efs_dns}:/ ${mount_dir} efs _netdev,noresvport,tls 0 0" >> /etc/fstab
fi

# Try mounting a few times; bail if still not mounted
tries=0
until mountpoint -q "${mount_dir}"; do
  mount -a || true
  tries=$((tries+1))
  [ "$tries" -ge 8 ] && break
  sleep 5
done
mountpoint -q "${mount_dir}" || { echo "EFS not mounted at ${mount_dir}, aborting"; exit 1; }

# Gitea filesystem on EFS
mkdir -p "${mount_dir}"/{data,log,custom}
id -u git &>/dev/null || useradd -r -m -s /sbin/nologin git
chown -R git:git "${mount_dir}"
chmod -R 750 "${mount_dir}"

# Fetch DB creds (retry)
i=0
until SECRET_JSON="$(aws --region "${aws_region}" secretsmanager get-secret-value --secret-id "${db_secret_arn}" --query SecretString --output text 2>/dev/null)"; do
  i=$((i+1)); [ $i -ge 12 ] && SECRET_JSON='{}' && break; sleep 5
done
db_user="$(echo "$SECRET_JSON" | jq -r '.username // "gitea"')"
db_pass="$(echo "$SECRET_JSON" | jq -r '.password // "changeme"')"

# Install Gitea (arch-aware; escape $${...} for TF)
ARCH="$(uname -m)"; BIN_ARCH="linux-amd64"; [ "$ARCH" = "aarch64" ] && BIN_ARCH="linux-arm64"
if [ ! -x /usr/local/bin/gitea ]; then
  wget -qO /usr/local/bin/gitea "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-$${BIN_ARCH}"
  chmod +x /usr/local/bin/gitea
fi

# app.ini — bind 0.0.0.0, correct URL, Postgres with TLS
cat > "${mount_dir}/custom/app.ini" <<EOF
[server]
HTTP_ADDR = 0.0.0.0
HTTP_PORT = ${app_port}
PROTOCOL  = http
DOMAIN    = ${alb_dns}
ROOT_URL  = http://${alb_dns}/
APP_DATA_PATH = ${mount_dir}

[database]
DB_TYPE  = postgres
HOST     = ${db_host}:${db_port}
NAME     = ${db_name}
USER     = $${db_user}
PASSWD   = $${db_pass}
SCHEMA   = public
SSL_MODE = require

[log]
MODE  = console
LEVEL = info

[repository]
ROOT = ${mount_dir}/data/git/repositories

[session]
PROVIDER = file
PROVIDER_CONFIG = ${mount_dir}/data/sessions

[security]
INSTALL_LOCK = true

[queue]
TYPE = channel   # or redis with CONN_STR
EOF
chown -R git:git "${mount_dir}"

# Systemd unit (env forces TLS; wait for DB & EFS)
# NOTE: heredoc is *unquoted* so variables expand here.
cat > /etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network-online.target remote-fs.target
Wants=network-online.target
RequiresMountsFor=${mount_dir}

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/home/git
Environment="GITEA__database__SSL_MODE=require"
Environment="GITEA_WORK_DIR=${mount_dir}"
Environment="GITEA_CUSTOM=${mount_dir}/custom"
Environment="GITEA__queue__TYPE=channel"
# Light readiness check (no password needed)
ExecStartPre=/usr/bin/pg_isready -h ${db_host} -p ${db_port} -t 5
ExecStart=/usr/local/bin/gitea web --config ${mount_dir}/custom/app.ini
Restart=always
RestartSec=2
TimeoutStopSec=25
KillSignal=SIGTERM
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gitea

echo "Gitea up on port ${app_port} — $(date -Is)"
# ----------------------------- / user-data.sh --------------------------------
