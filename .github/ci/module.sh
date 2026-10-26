#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build the module against the distribution kernel headers of this
# container, with warnings as errors. Run from the repository root.
set -eu
. /etc/os-release
case "$ID" in
debian)
	apt-get update -q
	apt-get install -qy --no-install-recommends make gcc linux-headers-amd64 ;;
ubuntu)
	apt-get update -q
	apt-get install -qy --no-install-recommends make gcc linux-headers-generic ;;
fedora)
	dnf install -qy make gcc kernel-devel ;;
arch)
	pacman -Syu --noconfirm --needed make gcc linux-headers ;;
*)
	echo "unknown distribution: $ID" >&2
	exit 1 ;;
esac
for kdir in /usr/src/linux-headers-*-amd64 /usr/src/linux-headers-*-generic \
	    /usr/src/kernels/* /usr/lib/modules/*/build; do
	[ -f "$kdir/Makefile" ] && break
done
[ -f "$kdir/Makefile" ] || { echo "no kernel headers found" >&2; exit 1; }
echo "Building against $kdir"
make -C kernel/gpu_unlock KDIR="$kdir" KCFLAGS=-Werror
test -f kernel/gpu_unlock/gpu_unlock.ko
