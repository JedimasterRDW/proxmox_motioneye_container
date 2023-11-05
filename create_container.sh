#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT
function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  [ ! -z ${CTID-} ] && cleanup_failed
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function cleanup_failed() {
  if [ ! -z ${MOUNT+x} ]; then
    pct unmount $CTID
  fi
  if $(pct status $CTID &>/dev/null); then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID
    fi
    pct destroy $CTID
  elif [ "$(pvesm list $STORAGE --vmid $CTID)" != "" ]; then
    pvesm free $ROOTFS
  fi
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

# Download setup script
wget -qL https://raw.githubusercontent.com/JedimasterRDW/proxmox_motioneye_container/master/setup.sh

# Select storage location
STORAGE_LIST=( $(pvesm status -content rootdir | awk 'NR>1 {print $1}') )
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
  warn "'Container' needs to be selected for at least one storage location."
  die "Unable to detect valid storage location."
elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
  STORAGE=${STORAGE_LIST[0]}
else
  msg "\n\nMore than one storage locations detected.\n"
  PS3=$'\n'"Which storage location would you like to use? "
  select s in "${STORAGE_LIST[@]}"; do
    if [[ " ${STORAGE_LIST[@]} " =~ " ${s} " ]]; then
      STORAGE=$s
      break
    fi
    echo -en "\e[1A\e[K\e[1A"
  done
fi
info "Using '$STORAGE' for storage location."

# Get the next guest VM/LXC ID
CTID=$(pvesh get /cluster/nextid)
info "Container ID is $CTID."

# Download latest Debian LXC template
msg "Updating LXC template list..."
pveam update >/dev/null
msg "Downloading LXC template..."
OSTYPE=debian
OSVERSION=${OSTYPE}-11
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($OSVERSION.*\)/\1/p" | sort -t - -k 2 -V)
TEMPLATE="${TEMPLATES[-1]}"
pveam download local $TEMPLATE >/dev/null ||
  die "A problem occured while downloading the LXC template."

# Create variables for container disk
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  dir|nfs)
    DISK_EXT=".raw"
    DISK_REF="$CTID/"
    ;;
  zfspool)
    DISK_PREFIX="subvol"
    DISK_FORMAT="subvol"
    ;;
esac
DISK=${DISK_PREFIX:-vm}-${CTID}-disk-0${DISK_EXT-}
ROOTFS=${STORAGE}:${DISK_REF-}${DISK}

# Create LXC
ARCH=$(dpkg --print-architecture)
HOSTNAME=motioneye
TEMPLATE_STRING="local:vztmpl/${TEMPLATE}"
echo "Do you want a privileged container?(yes/no)"
read input
if [ "$input" == "yes" ]; then
msg "Creating Privileged LXC container..."
pct create $CTID $TEMPLATE_STRING -arch $ARCH -cores 1 -hostname $HOSTNAME \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp -onboot 1 -ostype $OSTYPE \
  -password "motioneye" -storage $STORAGE >/dev/null
else
msg "Creating UnPrivileged LXC container..."
pct create $CTID $TEMPLATE_STRING -arch $ARCH -cores 1 -hostname $HOSTNAME \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp -onboot 1 -ostype $OSTYPE \
  -password "motioneye" -storage $STORAGE -unprivileged 1 >/dev/null
fi

# Set container timezone to match host
MOUNT=$(pct mount $CTID | cut -d"'" -f 2)
ln -fs $(readlink /etc/localtime) ${MOUNT}/etc/localtime
pct unmount $CTID && unset MOUNT

# Setup container for MotionEye
msg "Starting LXC container..."
pct start $CTID
pct push $CTID setup.sh /setup.sh -perms 755
pct exec $CTID -- bash -c "/setup.sh"

# Get network details and show completion message
IP=$(pct exec $CTID ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
info "Successfully created MotionEye LXC to $CTID."
msg "

MotionEye is reachable by going to the following URLs.

      http://${IP}:8765
      
  MotiuonEye WebUI Login: admin
                Password: "No Password"
  
  MotiuonEye Terminal Login: root
                   Password: motioneye
              
"
