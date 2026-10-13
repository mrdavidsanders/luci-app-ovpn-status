'use strict';
'require view';
'require dom';
'require uci';
'require form';

// Configuration page for the OpenVPN status collector.
//
// Maps onto the UCI config /etc/config/openvpn_status (section type
// 'openvpn_status', name 'main'). Saving restarts the 'openvpn-status'
// init script so the new mode / SSH endpoint takes effect immediately.
return view.extend({
	render: function() {
		const m = new form.Map('openvpn_status', _('OpenVPN Status'));

		const s = m.section(form.TypedSection, 'openvpn_status',
			_('Collector'),
			_('Where the OpenVPN client status is collected from.'));
		s.addremove = false;
		s.anonymous = false;

		// --- mode: local (server) vs remote (client over SSH) ------------
		const mode = s.option(form.ListValue, 'mode', _('Collection mode'),
			_('Collect from the local OpenVPN daemon, or fetch it from a ' +
			 'remote server over SSH.'));
		mode.value('server', _('Local (this device)'));
		mode.value('client', _('Remote (over SSH)'));
		mode.default = 'server';
		mode.rmempty = false;

		// --- show the widget on the Status Overview page -----------------
		const overview = s.option(form.Flag, 'show_on_overview',
			_('Show on Status Overview'),
			_('Also display the client table on the main Status Overview ' +
			 'page. When enabled, the dedicated "OpenVPN Status" page is ' +
			 'hidden to avoid showing it twice.'));
		overview.default = '0';
		overview.rmempty = false;

		// --- interval: seconds between collection runs -------------------
		const interval = s.option(form.Value, 'interval', _('Interval (seconds)'),
			_('How often the collector refreshes the status data.'));
		interval.datatype = 'range(5, 3600)';
		interval.placeholder = '60';
		interval.default = '60';
		interval.rmempty = false;

		// --- SSH endpoint (client mode only) -----------------------------
		const ssh_user = s.option(form.Value, 'ssh_user', _('SSH user'),
			_('Username used to log in to the remote server.'));
		ssh_user.datatype = 'string';
		ssh_user.placeholder = 'vpnstatus';
		ssh_user.depends({ mode: 'client' });

		const ssh_host = s.option(form.Value, 'ssh_host', _('SSH host'),
			_('Hostname or IP address of the remote OpenVPN server. ' +
			 'The key used for authentication is the device\'s default ' +
			 'SSH key (see the "SSH keys" system setting).'));
		ssh_host.datatype = 'ip4';
		ssh_host.placeholder = '192.168.1.10';
		ssh_host.depends({ mode: 'client' });

		const max_tries = s.option(form.Value, 'max_tries', _('Max connection attempts'),
			_('How many times to retry the SSH connection before giving up ' +
			 'on a single collection cycle.'));
		max_tries.datatype = 'range(1, 50)';
		max_tries.placeholder = '3';
		max_tries.default = '3';
		max_tries.rmempty = false;
		max_tries.depends({ mode: 'client' });

		// Restart the collector after a successful save so the new
		// settings take effect without a reboot.
		m.apply = function() {
			return m.super('apply').then(function() {
				return L.sys.call('restart', ['openvpn-status']);
			});
		};

		return m.render();
	}
});
