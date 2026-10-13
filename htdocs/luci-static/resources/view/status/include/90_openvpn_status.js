'use strict';
'require baseclass';
'require uci';
'require fs';

// Status-Overview include for the OpenVPN client table.
//
// The Status Overview page (view/status/index.js) auto-loads every *.js in
// view/status/include/. We return `null` from render() when the
// "show_on_overview" flag is disabled, which makes the Overview skip this
// section entirely. The flag is toggled in Services -> OpenVPN Status.
const STATUS_FILE = '/tmp/openvpn_new.json';

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

return baseclass.extend({
	title: _('OpenVPN Clients'),

	load: function() {
		return Promise.all([
			uci.load('openvpn_status'),
			fs.read(STATUS_FILE).catch(function() { return '[]'; })
		]);
	},

	render: function(data) {
		const [clientsRaw] = data;

		// Hidden unless the user enabled it in the config panel.
		if (uci.get('openvpn_status', 'main', 'show_on_overview') != '1')
			return null;

		let clients;
		try {
			clients = JSON.parse(clientsRaw || '[]');
		} catch (e) {
			clients = [];
		}

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

		if (!Array.isArray(clients) || clients.length === 0) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', colspan: 6 }, [ _('No OpenVPN status data available') ])
			]));
		} else {
			for (const c of clients) {
				const [v4, v6] = splitAddrs(c['Virtual Address']);
				table.appendChild(E('tr', { 'class': 'tr cbi-rowstyle-1' }, [
					E('td', { 'class': 'td', 'data-title': _('Common Name') }, [ c['Common Name'] ]),
					E('td', { 'class': 'td', 'data-title': _('VPN v4 / v6') }, [ v4 + ' / ' + v6 ]),
					E('td', { 'class': 'td', 'data-title': _('Remote Address') }, [ c['Real Address'] ]),
					E('td', { 'class': 'td', 'data-title': _('RX / TX') }, [
						humanBytes(c['Bytes Received']) + ' / ' + humanBytes(c['Bytes Sent'])
					]),
					E('td', { 'class': 'td', 'data-title': _('Connected') }, [ c['Connected Since'] ]),
					E('td', { 'class': 'td', 'data-title': _('Refreshed') }, [ c['Last Ref'] ])
				]));
			}
		}

		return table;
	}
});
