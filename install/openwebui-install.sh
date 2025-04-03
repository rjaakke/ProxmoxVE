#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck
# Co-Author: havardthom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openwebui.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  gpg \
  git \
  ffmpeg
msg_ok "Installed Dependencies"

msg_info "Setting up Intel® Repositories"
mkdir -p /etc/apt/keyrings
curl -fsSL https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor -o /etc/apt/keyrings/intel-graphics.gpg
echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble unified" >/etc/apt/sources.list.d/intel-gpu-noble.list
curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor -o /etc/apt/keyrings/oneapi-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" >/etc/apt/sources.list.d/oneAPI.list
$STD apt-get update
msg_ok "Set up Intel® Repositories"

msg_info "Setting Up Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools,libze-intel-gpu1,libze1,clinfo,intel-gsc,libze-dev,intel-ocloc}
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
fi
msg_ok "Set Up Hardware Acceleration"

msg_info "Setup Python3"
$STD apt-get install -y --no-install-recommends \
  python3 \
  python3-pip
msg_ok "Setup Python3"

msg_info "Setting up Node.js Repository"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
msg_ok "Set up Node.js Repository"

msg_info "Installing Node.js"
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Installing Open WebUI (Patience)"
$STD git clone https://github.com/open-webui/open-webui.git /opt/open-webui
cd /opt/open-webui/backend
$STD pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
$STD pip3 install -r requirements.txt -U
cd /opt/open-webui
cp .env.example .env
cat <<EOF >/opt/open-webui/.env
ENV=prod
ENABLE_OLLAMA_API=false
OLLAMA_BASE_URL=http://0.0.0.0:11434
EOF
$STD npm install
export NODE_OPTIONS="--max-old-space-size=3584"
$STD npm run build
msg_ok "Installed Open WebUI"

read -r -p "Would you like to add Ollama? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Ollama"
  mkdir -p /opt/ollama
  curl -fsSLO https://github.com/intel/ipex-llm/releases/download/v2.2.0-nightly/ollama-ipex-llm-2.2.0b20250318-ubuntu.tgz
  tar -C /opt/ollama -xzf ollama-ipex-llm-2.2.0b20250318-ubuntu.tgz
  rm -rf ollama-ipex-llm-2.2.0b20250318-ubuntu.tgz
  cat <<EOF >/etc/systemd/system/ollama.service
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=exec
ExecStart=/usr/bin/ollama serve
Environment=HOME=$HOME
Environment=OLLAMA_HOST=0.0.0.0
Environment=OLLAMA_NUM_GPU=999
Environment=no_proxy=localhost,127.0.0.1
Environment=ZES_ENABLE_SYSMAN=1
Environment=SYCL_CACHE_PERSISTENT=1
Environment=OLLAMA_KEEP_ALIVE=10m
# [optional] under most circumstances, the following environment variable may improve performance, but sometimes this may also cause performance degradation
Environment=SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1
# [optional] if you want to run on single GPU, use below command to limit GPU may improve performance
# Environment=ONEAPI_DEVICE_SELECTOR=level_zero:0
# If you have more than one dGPUs, according to your configuration you can use configuration like below, it will use the first and second card.
# Environment=ONEAPI_DEVICE_SELECTOR="level_zero:0;level_zero:1"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ollama
  sed -i 's/ENABLE_OLLAMA_API=false/ENABLE_OLLAMA_API=true/g' /opt/open-webui/.env
  msg_ok "Installed Ollama"
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/open-webui
EnvironmentFile=/opt/open-webui/.env
ExecStart=/opt/open-webui/backend/start.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now open-webui
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
