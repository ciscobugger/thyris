#!/bin/bash
# One-time setup of the check machine: Docker, an Arch image with what Opsis builds and runs its checks with, and CEF
# for x86_64 (the same version as the laptop's).
set -e
mkdir -p ~/opsis && cd ~/opsis
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io >/dev/null
# Chromium's sandbox makes user namespaces as a normal user; Ubuntu 24.04 refuses that by default
echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/60-opsis-userns.conf >/dev/null
sudo sysctl -q --system
cat > Dockerfile <<DOCKER
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed base-devel cmake ninja git rust \
    qt6-base qt6-declarative qt6-webengine qt6-webchannel qt6-shadertools qt6-svg qt6-imageformats \
    cups sqlite nss openssl dbus gnome-keyring libsecret hunspell fontconfig ttf-liberation noto-fonts \
    gtk3 alsa-lib at-spi2-core libdrm libxkbcommon libxcomposite libxdamage libxrandr mesa pango cairo libglvnd \
    python procps-ng which unzip bzip2 && pacman -Scc --noconfirm
# the laptop's language: the engine tells pages the system's
RUN echo 'en_GB.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen
RUN useradd -m -u $(id -u) abdul
USER abdul
WORKDIR /work
DOCKER
sudo docker build --network=host -q -t opsis-arch .
sudo docker run --rm opsis-arch pacman -Q qt6-base qt6-webengine qt6-declarative cmake rust gcc
if [ ! -d cef ]; then
    curl -fsSL -o cef.tar.bz2 "https://cef-builds.spotifycdn.com/cef_binary_154.0.34%2Bg14c5a08%2Bchromium-154.0.8037.98_linux64.tar.bz2"
    tar xjf cef.tar.bz2 && rm cef.tar.bz2 && mv cef_binary_154.0.34+g14c5a08+chromium-154.0.8037.98_linux64 cef
    # the data files go beside libcef.so
    cp -r cef/Resources/* cef/Release/
fi
echo SETUP-DONE
