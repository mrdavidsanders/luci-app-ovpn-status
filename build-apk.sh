#!/bin/sh
# build-apk.sh - build an Alpine .apk for luci-app-openvpn-status
#
# Newer OpenWrt images can optionally run the Alpine `apk` package manager
# (see openwrt package/system/apk, gated by USE_APK). This script produces a
# .apk for such images, in parallel with the opkg .ipk.
#
# An .apk is:  control.tar.gz  +  data.tar.gz  (+ an appended RSA signature).
#   - control.tar.gz holds .PKGINFO (flat "key = value" fields) and any
#     lifecycle scripts (.POSTINSTALL etc.).
#   - data.tar.gz is a POSIX (pax) tarball of the payload, root-owned, with
#     paths RELATIVE to the payload root (so files land at /usr/..., /etc/...).
#
# The payload is exactly the same tree luci.mk installs for the .ipk: the
# root/ tree plus the htdocs/ tree (no luasrc/ucode/.po for this app).
#
# NOTE: this builds an UNSIGNED package (no apk-tools / signing key here).
# `apk add` will refuse to install it unless you sign it first:
#     abuild-sign -k /path/to/privkey.pem <pkg>.apk
# or add it to a local repo with a trusted key. For a one-off on-device
# install you can also use:  apk add --force-untrusted <pkg>.apk
#
# Requires: sh, tar (pax/posix), gzip, sha256sum. Run from the package root.

set -e

PKGNAME=luci-app-openvpn-status
PKGVER=0.0.9
PKGREL=1
ARCH=noarch
MAINTAINER="David Sanders <david@kubology.uk>"
LICENSE="Apache-2.0"
URL="https://github.com/openwrt/luci"
DESCRIPTION="Displays active OpenVPN clients on the LuCI status page"
DEPS="luci-base"

# Reproducible timestamp (seconds since epoch).
: "${SOURCE_DATE_EPOCH:=$(date -u +%s)}"

OUT=${OUT:-/tmp/apkbuild}
rm -rf "$OUT"
mkdir -p "$OUT/payload" "$OUT/control"

# --- 1. Payload: root/ tree + htdocs/ tree (same as the .ipk) -------------
cp -a root/. "$OUT/payload/"
cp -a htdocs "$OUT/payload/htdocs"
chmod 0755 "$OUT/payload" "$OUT/payload/htdocs"

# --- 2. .PKGINFO control file --------------------------------------------
# isize/csize/datahash are computed below once the tarballs exist; we write a
# placeholder and patch the file, which is exactly what abuild does.
cat > "$OUT/control/.PKGINFO" <<EOF
pkgname = $PKGNAME
pkgver = $PKGVER-r$PKGREL
pkgdesc = $DESCRIPTION
url = $URL
arch = $ARCH
size = 0
origin = luci
license = $LICENSE
maintainer = $MAINTAINER
deps = $DEPS
EOF

# --- 3. data.tar.gz (pax/posix, root-owned, paths relative to payload) ----
(cd "$OUT/payload" && \
	tar --format=posix \
	    --pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
	    --owner=0 --group=0 --numeric-owner \
	    --mtime="@$SOURCE_DATE_EPOCH" \
	    -cf - . | gzip -n -9 > "$OUT/data.tar.gz")

# --- 4. control.tar.gz (just .PKGINFO for this app) -----------------------
# Patch the computed byte sizes/hash into .PKGINFO first (abuild uses bytes).
ISIZE=$(stat -c%s "$OUT/data.tar.gz")
CSIZE=0
DATAHASH=$(sha256sum "$OUT/data.tar.gz" | awk '{print $1}')
sed -i "s/^size = .*/size = $ISIZE/" "$OUT/control/.PKGINFO"
printf 'csize = %s\nisize = %s\ndatahash = %s\nbuilddate = %s\n' \
	"$CSIZE" "$ISIZE" "$DATAHASH" "$SOURCE_DATE_EPOCH" >> "$OUT/control/.PKGINFO"

(cd "$OUT/control" && \
	tar --format=posix \
	    --pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
	    --owner=0 --group=0 --numeric-owner \
	    --mtime="@$SOURCE_DATE_EPOCH" \
	    -cf - . | gzip -n -9 > "$OUT/control.tar.gz")
CSIZE=$(stat -c%s "$OUT/control.tar.gz")
sed -i "s/^csize = .*/csize = $CSIZE/" "$OUT/control/.PKGINFO"
# control.tar.gz changed after the csize patch; rebuild it once more.
(cd "$OUT/control" && \
	tar --format=posix \
	    --pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
	    --owner=0 --group=0 --numeric-owner \
	    --mtime="@$SOURCE_DATE_EPOCH" \
	    -cf - . | gzip -n -9 > "$OUT/control.tar.gz")

# --- 5. Assemble: control.tar.gz + data.tar.gz ----------------------------
APK="$PKGNAME-$PKGVER-r$PKGREL-$ARCH.apk"
cat "$OUT/control.tar.gz" "$OUT/data.tar.gz" > "$OUT/$APK"
cp "$OUT/$APK" ./"$APK"

echo "Built: ./$APK"
echo "  control.tar.gz: $(stat -c%s "$OUT/control.tar.gz") bytes"
echo "  data.tar.gz:    $(stat -c%s "$OUT/data.tar.gz") bytes"
echo "  sha256:         $(sha256sum "$OUT/$APK" | awk '{print $1}')"
echo
echo "UNSIGNED. To make it installable with 'apk add', sign it first:"
echo "  abuild-sign -k /path/to/privkey.pem ./$APK"
