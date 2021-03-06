#!/bin/sh
#
# Script to upgrade Libreswan on Ubuntu and Debian
#
# Copyright (C) 2016 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Check https://libreswan.org for the latest version
swan_ver=3.17

### Do not edit below this line ###

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: ${1}" >&2; exit 1; }
exiterr2() { echo "Error: 'apt-get install' failed." >&2; exit 1; }

os_type="$(lsb_release -si 2>/dev/null)"
if [ "$os_type" != "Ubuntu" ] && [ "$os_type" != "Debian" ]; then
  exiterr "This script only supports Ubuntu/Debian."
fi

if [ -f /proc/user_beancounters ]; then
  exiterr "This script does not support OpenVZ VPS."
fi

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo sh $0'"
fi

if [ -z "$swan_ver" ]; then
  exiterr "Libreswan version 'swan_ver' not specified."
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan"
if [ "$?" != "0" ]; then
  exiterr "This script requires Libreswan already installed."
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "$swan_ver"
if [ "$?" = "0" ]; then
  echo "You already have Libreswan version $swan_ver installed! "
  echo "If you continue, the same version will be re-installed."
  echo
  printf "Do you wish to continue anyway? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      echo "Aborting."
      exit 1
      ;;
  esac
fi

clear

cat <<EOF
Welcome! This script will build and install Libreswan $swan_ver on your server.
Additional packages required for Libreswan compilation will also be installed.

This is intended for use on servers running an older version of Libreswan.
Your existing VPN configuration files will NOT be modified.

EOF

if [ "$(sed 's/\..*//' /etc/debian_version 2>/dev/null)" = "7" ]; then
cat <<'EOF'
IMPORTANT: Workaround required for Debian 7 (Wheezy).
You must first run the script at: https://git.io/vpndeb7
Continue only after completing this workaround.

EOF
fi

printf "Do you wish to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    echo "Please be patient. Setup is continuing..."
    echo
    ;;
  *)
    echo "Aborting."
    exit 1
    ;;
esac

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || exiterr "Cannot enter /opt/src."

# Update package index and install Wget
export DEBIAN_FRONTEND=noninteractive
apt-get -yq update || exiterr "'apt-get update' failed."
apt-get -yq install wget || exiterr2

# Install necessary packages
apt-get -yq install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
  libcap-ng-dev libcap-ng-utils libselinux1-dev \
  libcurl4-nss-dev flex bison gcc make \
  libunbound-dev libnss3-tools libevent-dev || exiterr2
apt-get -yq --no-install-recommends install xmlto || exiterr2

# Compile and install Libreswan
swan_file="libreswan-$swan_ver.tar.gz"
swan_url1="https://download.libreswan.org/$swan_file"
swan_url2="https://github.com/libreswan/libreswan/archive/v$swan_ver.tar.gz"
wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url1" || wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url2"
[ "$?" != "0" ] && exiterr "Cannot download Libreswan source."
/bin/rm -rf "/opt/src/libreswan-$swan_ver"
tar xzf "$swan_file" && /bin/rm -f "$swan_file"
cd "libreswan-$swan_ver" || exiterr "Cannot enter Libreswan source dir."
echo "WERROR_CFLAGS =" > Makefile.inc.local
if [ "$(packaging/utils/lswan_detect.sh init)" = "systemd" ]; then
  apt-get -yq install libsystemd-dev || exiterr2
fi
make -s programs && make -s install

# Verify the install and clean up
cd /opt/src || exiterr "Cannot enter /opt/src."
/bin/rm -rf "/opt/src/libreswan-$swan_ver"
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "$swan_ver"
[ "$?" != "0" ] && exiterr "Libreswan $swan_ver failed to build."

# Restart IPsec service
service ipsec restart

echo
echo "Libreswan $swan_ver was installed successfully! "
echo

exit 0
