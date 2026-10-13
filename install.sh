#!/bin/sh
# install.sh - development install for luci-app-openvpn-status
#
# Installs the app DIRECTLY onto the running router, without building an
# IPK. Run this *on the router* after extracting the source tarball:
#
#     tar -xzf luci-app-openvpn-status-*.tgz
#     cd luci-app-openvpn-status
#     ./install.sh            # install (uses sample data)
#     ./install.sh --real     # install + use the REAL local collector
#
# Then open  http://<router>/  ->  Status  ->  OpenVPN Status
#
# To remove everything, run ./uninstall.sh
#
# This is for testing only. For a permanent install, build the IPK
# (make package/luci-app-openvpn-status/compile) and opkg install it.

set -e

PKG_NAME="luci-app-openvpn-status"

# --- Locate the WEB-SERVED LuCI view directory --------------------------
# The view .js must live where uhttpd serves it (the /www docroot), NOT in
# the package source dir. On overlayfs/apk routers (OpenWrt 25.x) /www is a
# union of /rom/www + /overlay/upper/www and is the actual web root.
#
#   resourcebase (uci luci.main.resourcebase)  ->  /luci-static/resources
#   web root (uci uhttpd.main.home)            ->  /www  (default)
#
# So the view dir = <web root><resourcebase>/view. We auto-detect both, with
# a fallback to the classic /usr/share/luci/html location.

RESOURCE_BASE=$(uci -q get luci.main.resourcebase 2>/dev/null)
[ -n "$RESOURCE_BASE" ] || RESOURCE_BASE="/luci-static/resources"

WEB_ROOT=$(uci -q get uhttpd.main.home 2>/dev/null)
[ -n "$WEB_ROOT" ] || WEB_ROOT="/www"

LUCI_VIEW_DIR="$WEB_ROOT$RESOURCE_BASE/view"

# Fallbacks for layouts that differ from the above.
if [ ! -d "$LUCI_VIEW_DIR" ]; then
    for cand in \
        "$WEB_ROOT$RESOURCE_BASE/view" \
        "/www/luci-static/resources/view" \
        "/usr/share/luci/html/resources/view" \
        "/usr/lib/lua/luci/view"; do
        if [ -d "$cand" ]; then
            LUCI_VIEW_DIR="$cand"
            break
        fi
    done
fi

if [ ! -d "$LUCI_VIEW_DIR" ]; then
    echo "ERROR: could not find the LuCI view directory." >&2
    echo "       Looked in: $LUCI_VIEW_DIR" >&2
    echo "       (Set LUCI_VIEW_DIR=/path/to/resources/view and re-run.)" >&2
    exit 1
fi

echo "Using view dir: $LUCI_VIEW_DIR"

# --- 1. Install the JavaScript views (into the WEB root) -----------------
VIEW_SRC="htdocs/luci-static/resources/view/openvpn_status"
VIEW_DST="$LUCI_VIEW_DIR/openvpn_status"

echo "Installing JS views -> $VIEW_DST"
mkdir -p "$VIEW_DST"
cp -f "$VIEW_SRC/index.js" "$VIEW_DST/index.js"
cp -f "$VIEW_SRC/config.js" "$VIEW_DST/config.js"

# --- 1b. Install the Status Overview include ----------------------------
# The Overview page auto-loads every *.js in view/status/include/. This file
# returns null from render() unless show_on_overview is enabled.
INCLUDE_SRC="htdocs/luci-static/resources/view/status/include/90_openvpn_status.js"
INCLUDE_DIR="$LUCI_VIEW_DIR/../status/include"
INCLUDE_DST="$INCLUDE_DIR/90_openvpn_status.js"

echo "Installing Status Overview include -> $INCLUDE_DST"
mkdir -p "$INCLUDE_DIR"
cp -f "$INCLUDE_SRC" "$INCLUDE_DST"

# --- 2. Install the menu entry -----------------------------------------
MENU_DIR="/usr/share/luci/menu.d"
MENU_DST="$MENU_DIR/$PKG_NAME.json"

echo "Installing menu -> $MENU_DST"
cp -f "root/usr/share/luci/menu.d/$PKG_NAME.json" "$MENU_DST"

# --- 2b. Install the rpcd ACL (so the JS view may read the JSON) --------
# LuCI's fs.read() calls the "file" ubus object, which rpcd gates by ACL.
# luci-base only grants file.list, so we must grant file.read on the JSON.
ACL_DIR="/usr/share/rpcd/acl.d"
ACL_DST="$ACL_DIR/$PKG_NAME.json"

echo "Installing rpcd ACL -> $ACL_DST"
cp -f "root/usr/share/rpcd/acl.d/$PKG_NAME.json" "$ACL_DST"

# --- 3. Install the collector scripts ----------------------------------
echo "Installing collector scripts -> /usr/bin"
cp -f root/usr/bin/openvpn-server-status.sh /usr/bin/openvpn-server-status.sh
cp -f root/usr/bin/openvpn-client-status.sh /usr/bin/openvpn-client-status.sh
chmod 0755 /usr/bin/openvpn-server-status.sh /usr/bin/openvpn-client-status.sh

# --- 3b. Seed the UCI config (idempotent) -------------------------------
# The dev install does NOT run /etc/uci-defaults (that is a first-boot,
# IPK-only mechanism). Without the config, any view that references
# "openvpn_status" via uci (e.g. the Status Overview depends block) fails
# with "RPC call to uci/get failed ... Resource not found". Create it from
# the bundled defaults, but only if it does not already exist so a re-run
# never clobbers the user's saved settings.
UCI_CONFIG="/etc/config/openvpn_status"
if [ ! -e "$UCI_CONFIG" ]; then
    echo "Seeding UCI config -> $UCI_CONFIG"
    cp -f root/etc/uci-defaults/openvpn_status "$UCI_CONFIG"
else
    echo "UCI config already present, leaving it untouched: $UCI_CONFIG"
fi

# --- 4. Seed the status JSON -------------------------------------------
# By default we seed the bundled sample data so the page renders
# immediately, even if OpenVPN / xan / csvkit are not set up yet.
# With --real we instead run the real local collector (needs xan or
# csvkit + jq, and a running OpenVPN server with status.log).
JSON_OUT="/tmp/openvpn_new.json"

if [ "$1" = "--real" ]; then
    echo "Running real collector (openvpn-server-status.sh)..."
    if /usr/bin/openvpn-server-status.sh; then
        echo "Collected real status -> $JSON_OUT"
    else
        echo "WARNING: real collector failed; seeding sample data instead" >&2
        cp -f test/openvpn_test.json "$JSON_OUT"
    fi
else
    echo "Seeding sample data -> $JSON_OUT"
    cp -f test/openvpn_test.json "$JSON_OUT"
fi

# --- 5. Clear LuCI caches so the new view + menu are picked up ---------
echo "Clearing LuCI caches..."
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true
# Reload rpcd so the new menu.d entry is registered (harmless if not needed).
/etc/init.d/rpcd reload 2>/dev/null || true

echo
echo "Done. Open  Status -> OpenVPN Status  in the LuCI web UI."
echo "(If the menu item does not appear, log out and back in, or reboot.)"
