#!/usr/bin/env bash
set -e

fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
mount -o remount,size=2G /tmp/
echo "Swap Allocated OK"

if [ ! "$BASH_VERSION" ] ; then
    echo "You must use bash to run this script. If running this script from curl, make sure the final word is 'bash'" 1>&2
    exit 1
fi

CURRENT_ARCH=$(dpkg --print-architecture)
if [[ "$CURRENT_ARCH" != "x64" && "$CURRENT_ARCH" != "amd64" && "$CURRENT_ARCH" != "arm64" ]]; then
    echo "$CURRENT_ARCH is not a supported cpu architecture for running Companion Satellite."
    echo "If you are running on an arm device (such as a Raspberry Pi), make sure to use an arm64 image."
    exit 1
fi

echo "This will attempt to install Companion Satellite as a system service on this device."
echo "It is designed to be run on headless servers, but can be used on desktop machines if you are happy to not have the tray icon."
echo "A user called 'satellite' will be created to run the service, and various scripts will be installed to manage the service"

if [ $(/usr/bin/id -u) -ne 0 ]; then
    echo "Must be run as root"
    exit 1
fi

# Install a specific stable build. It is advised to not use this, as attempting to install a build that doesn't
# exist can leave your system in a broken state that needs fixing manually
SATELLITE_BUILD="${SATELLITE_BUILD:-beta}"
# Development only: Allow building using a testing branch of this updater
SATELLITE_BRANCH="${SATELLITE_BRANCH:-main}"

# install some dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -yq git zip unzip curl libusb-1.0-0-dev libudev-dev cmake libfontconfig1 nano adduser wget
apt-get clean

# add a system user
id -u satellite &>/dev/null || adduser --disabled-password satellite --gecos ""

# install fnm to manage node version
# we do this to /opt/fnm, so that the satellite user can use the same installation
export FNM_DIR=/opt/fnm
echo "export FNM_DIR=/opt/fnm" >> /root/.bashrc
curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /opt/fnm &>/dev/null
export PATH=/opt/fnm:$PATH
eval "`fnm env --shell bash`"

BUILD_BRANCH=beta
if [ "$SATELLITE_BRANCH" == "stable" ]; then
    BUILD_BRANCH=stable
    SATELLITE_BRANCH=main
fi

echo "DEBUG"
echo "$BUILD_BRANCH"
echo "$SATELLITE_BUILD"
echo "DEBUG"

# clone the repository
rm -R /usr/local/src/companion-satellite &>/dev/null || true
git clone https://github.com/bitfocus/companion-satellite.git -b $SATELLITE_BRANCH /usr/local/src/companion-satellite
cd /usr/local/src/companion-satellite

# configure git for future updates
git config --global pull.rebase false

# run the update script
./pi-image/update.sh "$BUILD_BRANCH" false

# enable start on boot
systemctl enable satellite

# copy config file into place
cp ./pi-image/satellite-config /boot/satellite-config

# add the fnm node to this users path
# TODO - verify permissions
echo "export PATH=/opt/fnm/aliases/default/bin:\$PATH" >> /home/satellite/.bashrc

sudo sudo hostnamectl hostname "streampanel"
echo "Set hostname to \"streampanel\""

# check that a build of satellite was installed
if [ ! -d "/opt/companion-satellite" ] 
then
    echo "No Companion Satellite build was installed!\nIt should be possible to recover from this with \"sudo satellite-update\"" 
    exit 9999 # die with error code 9999
fi

# echo "Companion Satellite is installed!"
# echo "You can edit a subset of the configuration at \"/boot/satellite-config\" then can start it with \"sudo systemctl start satellite\" or \"sudo satellite-update\""
# echo "A http server will be started on port 9999 which gives access to the full configuration"

echo "==============="
sudo systemctl start satellite
LAN_IP=$(hostname -I | cut -d' ' -f1);
HOSTNAME=$(hostname);
echo "Companion Satellite can be configured at http://${LAN_IP}:9999 or http://${HOSTNAME}:9999";