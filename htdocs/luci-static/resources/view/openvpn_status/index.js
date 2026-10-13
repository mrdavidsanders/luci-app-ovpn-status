'use strict';
'require view';
'require dom';
'require fs';
'require ui';
'require tools.widgets as widgets';
'require uci';

// Path of the JSON file produced by the collector scripts
// (root/usr/bin/openvpn-server-status.sh / openvpn-client-status.sh).
const STATUS_FILE = '/tmp/openvpn_new.json';

// Human-readable byte size. Replaces the legacy filesize.lua helper.
function humanBytes(n) {
	n = +n || 0;
	const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
	let i = 0;
	while (n >= 1024 && i < units.length - 1) {
		n /= 1024;
		i++;
	}
	return n.toFixed((n >= 10 || i === 0) ? 0 : 2) + ' ' + units[i];
}

// Split a list of virtual addresses into [ipv4, ipv6].
// A real IPv6 check (contains ':') instead of the legacy "%a" heuristic.
function splitAddrs(vaddrs) {
	let v4 = '', v6 = '';
	for (const a of (vaddrs || [])) {
		if (typeof a === 'string' && a.includes(':'))
			v6 = a;
		else if (typeof a === 'string')
			v4 = a;
	}
	return [v4, v6];
}

// Build a single <tr> for one client. The dom/E() helper escapes text
// automatically, so the XSS risk of the old string-concatenated HTML is gone.
function clientRow(c) {
	const [v4, v6] = splitAddrs(c['Virtual Address']);
	return E('tr', { 'class': 'tr cbi-rowstyle-1' }, [
		E('td', { 'class': 'td', 'data-title': _('Common Name') }, [ c['Common Name'] ]),
		E('td', { 'class': 'td', 'data-title': _('VPN v4 / v6') }, [ v4 + ' / ' + v6 ]),
		E('td', { 'class': 'td', 'data-title': _('Remote Address') }, [ c['Real Address'] ]),
		E('td', { 'class': 'td', 'data-title': _('RX / TX') }, [
			humanBytes(c['Bytes Received']) + ' / ' + humanBytes(c['Bytes Sent'])
		]),
		E('td', { 'class': 'td', 'data-title': _('Connected') }, [ c['Connected Since'] ]),
		E('td', { 'class': 'td', 'data-title': _('Refreshed') }, [ c['Last Ref'] ])
	]);
}

return view.extend({
	// Exposed for unit testing (see test/view.test.js).
	humanBytes: humanBytes,
	splitAddrs: splitAddrs,
	clientRow: clientRow,

	// Hide this dedicated page when the widget is embedded on the
	// Status Overview (avoids showing it in two places at once).
	depends: {
		uci: {
			openvpn_status: {
				main: {
					show_on_overview: {
						anyof: { 1: null }
					}
				}
			}
		}
	},

	render: function() {
		const table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Common Name') ]),
				E('th', { 'class': 'th' }, [ _('VPN v4 / v6') ]),
				E('th', { 'class': 'th' }, [ _('Remote Address') ]),
				E('th', { 'class': 'th' }, [ _('RX / TX') ]),
				E('th', { 'class': 'th' }, [ _('Connected') ]),
				E('th', { 'class': 'th' }, [ _('Refreshed') ])
			])
		]);

		function refresh() {
			// Drop previously rendered body rows, keep the header row.
			table.querySelectorAll('tr:not(.table-titles)').forEach(function(r) {
				r.remove();
			});

			fs.read(STATUS_FILE).then(function(raw) {
				const clients = JSON.parse(raw || '[]');
				if (!Array.isArray(clients) || clients.length === 0) {
					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td', colspan: 6 }, [ _('No OpenVPN status data available') ])
					]));
					return;
				}
				for (const c of clients)
					table.appendChild(clientRow(c));
			}).catch(function() {
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', colspan: 6 }, [ _('No OpenVPN status data available') ])
				]));
			});
		}

		// Initial load plus a periodic auto-refresh (replaces the old
		// cron + page-reload approach).
		refresh();
		setInterval(refresh, 30 * 1000);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Active OpenVPN Clients') ]),
			table
		]);
	}
});
