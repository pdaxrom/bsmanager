# Build Server Manager

Chroot qemu environment for easy development and native crosscompilers.


To enable connection only from specific IP:

<pre>
iptables -A INPUT -p tcp --dport 41432 -s 37.252.126.129 -j ACCEPT
iptables -A INPUT -p tcp --dport 41432 -j DROP
</pre>

Example of armv7hf account on Ubuntu x86_64:

<pre>
sudo ./bsmanager.sh create armv7hf http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-armhf.tar.gz
sudo ./bsmanager.sh enable native armv7hf
sudo ./bsmanager.sh toolchain armv7hf ../buildtools_all_x86-64.tar.gz
sudo ./bsmanager.sh toolchain armv7hf ../arm-linux-gnueabihf-gcc_5.4.0_armv7hf_x86-64.tar.gz

ssh armv7hf@localhost
</pre>
