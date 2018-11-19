#!/usr/bin/env bash
set -e
if [ $# -ne 1 ] && [ $# -ne 2 ] ; then
    echo "Usage: prepare-service-container.sh <data-path> [code-path]"
    exit 1
fi

print_header () {
    printf "\n>>>>>>>> $1 <<<<<<<<\n\n"
}

print_header "Configuring image source"
bin/prepare-lxd.sh

lxc init ubuntu-minimal:18.04/amd64 snakepit

print_header "Configuring virtual drives"
uid=`ls -ldn "$1" | awk '{print $3}'`
lxc config set snakepit raw.idmap "both $uid 0"
lxc config device add snakepit data disk path=/data source="$1"
if [ $# -eq 2 ]; then
    lxc config device add snakepit code disk path=/code source="$2"
fi

print_header "Starting image..."
lxc start snakepit
exe="lxc exec snakepit -- "
$exe systemctl isolate multi-user.target

print_header "Installing dependencies..."
$exe bash -c 'DEBIAN_FRONTEND=noninteractive apt-get -yq update && \
    apt-get install -yq curl jq nodejs npm git build-essential'

if [ $# -ne 2 ]; then
    print_header "Cloning snakepit code base"
    $exe bash -c 'git clone https://github.com/mozilla/snakepit.git /code; cd /code; npm install'
fi

print_header "Getting endpoint address"
if lxc network show snakebr0 > /dev/null 2>&1; then
    address=`lxc network get snakebr0 ipv4.address`
else
    if ! lxc network show lxdbr0 > /dev/null 2>&1; then
        lxc network create lxdbr0
    fi
    address=`lxc network get lxdbr0 ipv4.address`
fi
address="`echo "$address" | cut -d/ -f 1`"
endpoint="https://${address}:8443"
echo "Using endpoint: $endpoint"

print_header "Configuring service..."
$exe /code/scripts/setup-service.sh 
