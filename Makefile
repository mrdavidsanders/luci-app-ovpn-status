# This is free software, licensed under the Apache License, Version 2.0 .
#
# luci-app-openvpn-status
#
# Modern (JavaScript) LuCI application that displays the list of active
# OpenVPN clients on the Status page. It is a rewrite of the legacy
# "luci-openvpn-status" module, which used the deprecated ucimap (.htm)
# view engine and server-side Lua HTML generation.
#
# Data is produced by the bundled collector scripts (see root/usr/bin and
# root/etc/init.d) into /tmp/openvpn_new.json and is read directly by the
# JavaScript view via the LuCI 'fs' module. No server-side HTML is built.

# --- Host-side development targets --------------------------------------
# These run on the build host and do NOT require the OpenWrt toolchain, so
# they are defined before the OpenWrt includes below (which only make sense
# inside a buildroot / luci feed).
#
#   make test        - run the JavaScript unit tests (requires node)
#   make shellcheck  - lint the shell scripts (requires shellcheck)

.PHONY: test shellcheck
test:
	@node test/view.test.js
shellcheck:
	@shellcheck root/usr/bin/openvpn-server-status.sh root/usr/bin/openvpn-client-status.sh root/etc/init.d/openvpn-status

# --- OpenWrt / LuCI buildroot build -------------------------------------
# The following only take effect when building inside the OpenWrt buildroot
# or the luci feed (where TOPDIR/rules.mk and luci.mk are present). The
# existence of $(TOPDIR)/rules.mk is used as a guard so that the host-side
# targets above (make test / make shellcheck) still work outside a buildroot.

ifneq ($(wildcard $(TOPDIR)/rules.mk),)

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openvpn-status
PKG_VERSION:=0.0.9
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=David Sanders <david@kubology.uk>

LUCI_TITLE:=LuCI OpenVPN status module
LUCI_DESCRIPTION:=Displays active OpenVPN clients on the LuCI status page
LUCI_DEPENDS:=+luci-base

# When this app is built inside the luci/ feed, luci.mk lives one level up.
# The fallback below allows building it standalone against a checkout of the
# luci repository (LUCI_MK points to the path of luci.mk).
-include $(LUCI_MK)

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature

else
# Outside a buildroot: nothing to build; host-side targets only.
endif


