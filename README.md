# luci-app-openvpn-status

A **modern (JavaScript) LuCI application** that displays the list of active
OpenVPN clients on the LuCI Status page.

This is a rewrite of the legacy [`luci-openvpn-status`](../luci-openvpn-status)
module. The old module used the **deprecated ucimap (`.htm`) view engine** and
built the table **server-side in Lua** by string-concatenating raw HTML. This
version uses the current LuCI JavaScript framework:

- The view is a **JavaScript module** (`view.extend`) that builds the table
  with the DOM helper `E()`. All text is escaped automatically (no XSS).
- Data is read **directly by the browser-side JS** via the LuCI `fs` module
  from `/tmp/openvpn_new.json` — there is no server-side HTML generation, no
  `luci.jsonc`, no Lua template.
- The page **auto-refreshes** every 30 seconds instead of relying on a cron
  run plus a manual page reload.
- It is packaged as a standard `luci-app-*` (proper `Makefile`, `root/`,
  `htdocs/`, `po/`), so it installs with `opkg`/the OpenWrt buildroot like any
  other LuCI app.

## Data flow

```
openvpn-server-status.sh  (local daemon)  ─┐
                                           ├─> /tmp/openvpn_new.json
openvpn-client-status.sh  (remote via SSH) ─┘            │
                                                         ▼
                        JS view (index.js) reads it with fs.read()
```

The collector scripts are unchanged in behaviour from the legacy module:
`openvpn-server-status.sh` parses the OpenVPN status log (via `xan` or
`csvkit` + `jq`) and `openvpn-client-status.sh` fetches the same JSON from a
remote host over SSH.

## Installing

### From the OpenWrt buildroot / luci feed
```
make package/luci-app-openvpn-status/{clean,compile,install}
```

### Building standalone
Point `LUCI_MK` at a checkout of the [luci](https://github.com/openwrt/luci)
repository (it must contain `luci.mk` at its top level):
```
make LUCI_MK=/path/to/luci/luci.mk
```

### Quick test on a running router (no IPK)
To try it on an existing OpenWrt router without building a package, extract
the source tarball on the router and run the dev installer:
```
tar -xzf luci-app-openvpn-status-*.tgz
cd luci-app-openvpn-status
./install.sh            # installs + seeds sample data (page renders immediately)
# or
./install.sh --real     # installs + runs the real local collector
```
Then open **Status → OpenVPN Status** in the LuCI web UI. The script copies the
JS view and menu entry into place, installs the collector scripts, seeds
`/tmp/openvpn_new.json`, and clears LuCI's caches. Remove it again with
`./uninstall.sh`.

> This is for testing only — it is not tracked by `opkg`. For a permanent
> install, build the IPK and `opkg install` it.

## Configuration

The settings are edited in the LuCI web UI under **Services → OpenVPN Status**,
which writes to `/etc/config/openvpn_status` and restarts the `openvpn-status`
collector on save. The same options can be set from the shell:

```
config 'openvpn_status' 'main'
    option 'mode' 'server'        # "server" (local) or "client" (remote SSH)
    option 'interval' '60'        # seconds between collection runs
    option 'show_on_overview' '0' # also show the table on Status Overview
    option 'ssh_user' ''          # client mode only
    option 'ssh_host' ''          # client mode only
    option 'max_tries' '3'        # client mode only
```

Enabling **Show on Status Overview** embeds the client table on the main
Status Overview page (and hides the dedicated *OpenVPN Status* page to avoid
showing it twice).

### Server mode (local OpenVPN daemon)
Install the collector and a cron entry (or start the bundled init script):
```
/etc/init.d/openvpn-status enable
/etc/init.d/openvpn-status start
```
or via cron:
```
*/1 * * * * /usr/bin/openvpn-server-status.sh 2>&1 | /usr/bin/logger -t luci-openvpn-status
```
`server_status` requires `xan` (fast, recommended) or `csvkit`, plus `jq`.

### Client mode (remote OpenVPN server)
```
uci set openvpn_status.main.mode='client'
uci set openvpn_status.main.ssh_user='vpn'
uci set openvpn_status.main.ssh_host='vpn.example.com'
uci commit openvpn_status
```
The remote host must run a forced command that prints the status JSON (the
same schema `openvpn-server-status.sh` produces).

## Layout

```
luci-app-openvpn-status/
├── Makefile
├── install.sh                          # dev install on a running router (no IPK)
├── uninstall.sh                        # remove the dev install
├── htdocs/luci-static/resources/view/openvpn_status/index.js   # status JS view
├── htdocs/luci-static/resources/view/openvpn_status/config.js  # config formview
├── htdocs/luci-static/resources/view/status/include/90_openvpn_status.js  # Overview widget
├── root/
│   ├── etc/init.d/openvpn-status            # procd init script
│   ├── etc/uci-defaults/openvpn_status      # default UCI config
│   ├── usr/bin/openvpn-server-status.sh     # local collector
│   ├── usr/bin/openvpn-client-status.sh     # remote (SSH) collector
│   ├── usr/share/luci/menu.d/luci-app-openvpn-status.json  # menu entry
│   └── usr/share/rpcd/acl.d/luci-app-openvpn-status.json  # rpcd ACL (file.read)
├── po/templates/openvpn-status.pot          # i18n template
└── test/
    ├── openvpn_test.json                    # sample data
    └── view.test.js                         # Node unit tests
```

## Testing

The data-transformation logic in the JS view is unit-tested with Node (no
browser or LuCI required):
```
make test
```

## Authors
- mrdavidsanders <david at kubology dot uk>
- sebabordon <sebasb@outlook.com>
