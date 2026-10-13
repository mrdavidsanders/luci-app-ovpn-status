#!/bin/sh
# uninstall.sh - remove the dev install of luci-app-openvpn-status
#
# Reverses install.sh. Run this *on the router*:
#
#     ./uninstall.sh

PKG_NAME="luci-app-openvpn-status"

# Locate the web-served view dir the same way install.sh does.
RESOURCE_BASE=$(uci -q get luci.main.resourcebase 2>/dev/null)
[ -n "$RESOURCE_BASE" ] || RESOURCE_BASE="/luci-static/resources"
WEB_ROOT=$(uci -q get uhttpd.main.home 2>/dev/null)
[ -n "$WEB_ROOT" ] || WEB_ROOT="/www"
LUCI_VIEW_DIR="$WEB_ROOT$RESOURCE_BASE/view"

echo "Removing JS view (web root)..."
rm -rf "$LUCI_VIEW_DIR/openvpn_status" 2>/dev/null || true
# Remove the Status Overview include.
rm -f "$LUCI_VIEW_DIR/../status/include/90_openvpn_status.js" 2>/dev/null || true
# Also remove a copy that may have been placed in the package source dir
# by an older version of install.sh.
rm -rf /usr/share/luci/html/resources/view/openvpn_status 2>/dev/null || true

echo "Removing menu entry..."
rm -f "/usr/share/luci/menu.d/$PKG_NAME.json" 2>/dev/null || true

echo "Removing rpcd ACL..."
rm -f "/usr/share/rpcd/acl.d/$PKG_NAME.json" 2>/dev/null || true

echo "Removing collector scripts..."
rm -f /usr/bin/openvpn-server-status.sh /usr/bin/openvpn-client-status.sh 2>/dev/null || true

echo "Removing status JSON..."
rm -f /tmp/openvpn_new.json 2>/dev/null || true

echo "Clearing LuCI caches..."
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true
/etc/init.d/rpcd reload 2>/dev/null || true

echo
echo "Removed. Log out and back in (or reboot) to drop the menu item."
