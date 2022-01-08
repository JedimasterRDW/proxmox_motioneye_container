#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

# Prepare container OS
msg "Setting up container OS..."
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
apt-get -y purge openssh-{client,server} >/dev/null
apt-get autoremove >/dev/null

# Update container OS
msg "Updating container OS..."
apt-get update >/dev/null
apt-get -qqy upgrade &>/dev/null

# Install prerequisites
# Install motion ffmpeg v4l-utils
msg "Installing necessary components..."
apt-get install motion ffmpeg v4l-utils -y &>/dev/null
systemctl stop motion
systemctl disable motion

# Install pip2
msg "Installing pip2..."
apt-get install python2 curl -y &>/dev/null
curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py &>/dev/null
python2 get-pip.py &>/dev/null

# Update
apt-get update &>/dev/null

# Install the dependencies
msg "Installing dependencies..."
apt-get install python-dev-is-python2 python-setuptools libssl-dev libcurl4-openssl-dev libjpeg-dev zlib1g-dev libffi-dev libzbar-dev libzbar0 -y &>/dev/null

# Add /usr/local/bin to PATH
export PATH=$PATH:/usr/local/bin

# Install MotionEye
msg "Installing MotionEye..."
# yes 2>/dev/null | 
pip2 install motioneye &>/dev/null

# Prepare the configuration
msg "Prepare the configuration..."
mkdir -p /etc/motioneye
cp /usr/local/share/motioneye/extra/motioneye.conf.sample /etc/motioneye/motioneye.conf

# Prepare the media directory
msg "Prepare the media directory..."
mkdir -p /var/lib/motioneye

# configure run at startup and start the motionEye server
msg "Prepare run at startup and start the motionEye server..."
cp /usr/local/share/motioneye/extra/motioneye.systemd-unit-local /etc/systemd/system/motioneye.service
systemctl daemon-reload
systemctl enable motioneye
systemctl start motioneye

# Cleanup container
msg "Cleanup..."
rm -rf /setup.sh /var/{cache,log}/* /var/lib/apt/lists/*
