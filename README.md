# Build Server Manager

Chroot qemu environment for easy development and native crosscompilers.


To enable connection only from specific IP:

<pre>
iptables -A INPUT -p tcp --dport 41432 -s 37.252.126.129 -j ACCEPT
iptables -A INPUT -p tcp --dport 41432 -j DROP
</pre>

## Root filesystems for virtual accounts:

<pre>
ARM64              http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-arm64.tar.gz
ARMv7 HF           http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-armhf.tar.gz
x86_64 (amd64)     http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-amd64.tar.gz
Raspberry PI (one) http://cctools.info/downloads/root-eabi-armv6hf.tar.bz2
</pre>

## Example of armv7hf account with full buildserver toolchains on Ubuntu x86_64:

<pre>
sudo ./bsmanager.sh create armv7hf http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-armhf.tar.gz
sudo ./bsmanager.sh enable native armv7hf
sudo ./bsmanager.sh toolchain armv7hf https://shell.buildserver.io/downloads/buildtools_all_x86-64.tar.gz
sudo ./bsmanager.sh toolchain armv7hf https://shell.buildserver.io/downloads/arm-linux-gnueabihf-gcc_5.4.0_armv7hf_x86-64.tar.gz

ssh armv7hf@localhost
</pre>

## Example of arm64 ubuntu account with buildserver crosscompiler installed on Ubuntu x86_64 host:

- Setup base system:

<pre>
sudo ./bsmanager.sh create arm64 http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-arm64.tar.gz
</pre>

- Login to arm64 root shell:

<pre>
sudo ./bsmanager.sh shell arm64
</pre>

- Select preferred locales (en_US.UTF-8 pl_PL.UTF-8 ru_RU.UTF-8: 149 364 378):

<pre>
dpkg-reconfigure locales
</pre>

- Update packages:

<pre>
sed -i -e 's|# deb |deb |g' /etc/apt/sources.list
apt update
apt install -y dialog nano openssh-client
apt full-upgrade -y
</pre>

- Setup build environment:

<pre>
apt install -y build-essential pkg-config m4 perl python rpm ccache
</pre>

- Disable dash as default shell (/dev/sh):

<pre>
dpkg-reconfigure dash
</pre>

- Exit from arm64 root shell:

<pre>
exit
</pre>

- Enable host native utils and cross toolchain:

<pre>
sudo ./bsmanager.sh enable native arm64
sudo ./bsmanager.sh toolchain arm64 https://shell.buildserver.io/downloads/aarch64-linux-gnu-gcc_5.4.0_arm64_x86-64.tar.gz
</pre>

- Login to arm64 shell:

<pre>
ssh arm64@<buildserver IP>
</pre>

- Check home directory for *-setenv files and setup environment:

<pre>
source aarch64-linux-gnu-setenv
</pre>

Now your system is fully configured for arm64 development!
