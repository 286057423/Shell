#!/bin/bash
# ==================================================
# Author: Ops
# Desc  : Docker install for CentOS 7 (Production)
# ==================================================

set -e

### 可调整参数 ###
DOCKER_VERSION="20.10.24"
DOCKER_YUM_REPO="https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"

### 日志函数 ###
log() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

err() {
    echo -e "\033[31m[ERROR]\033[0m $1"
    exit 1
}

### root 权限检查 ###
[ "$(id -u)" -eq 0 ] || err "请使用 root 用户执行"


### 卸载旧 Docker ###
log "卸载旧版本 Docker（如存在）"

yum remove -y docker* containerd.io || true

### 安装依赖 ###
log "安装依赖包"

yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2

### 配置阿里云 Docker 仓库 ###
log "配置 Docker YUM 仓库（阿里云）"

yum-config-manager --add-repo ${DOCKER_YUM_REPO}

yum makecache fast

### 安装指定版本 Docker ###
log "安装 Docker ${DOCKER_VERSION}"

yum install -y \
    docker-ce-${DOCKER_VERSION} \
    docker-ce-cli-${DOCKER_VERSION} \
    containerd.io

### Docker 目录准备 ###
mkdir -p /etc/docker

### Docker daemon 配置 ###
log "生成 Docker daemon 配置"

cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

### 启动 Docker ###
log "启动 Docker 服务"

systemctl daemon-reload
systemctl enable docker
systemctl restart docker

### Docker 状态检查 ###
log "检查 Docker 状态"

systemctl is-active docker >/dev/null || err "Docker 启动失败"

docker version >/dev/null 2>&1 || err "Docker 客户端异常"

log "Docker 安装完成"
docker --version

