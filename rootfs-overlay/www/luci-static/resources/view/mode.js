'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

function actionButton(label, style, cmd) {
	return E('button', {
		'class': 'cbi-button cbi-button-' + style,
		'click': function(ev) {
			ev.currentTarget.disabled = true;
			return fs.exec('/usr/sbin/mode', [ cmd ]).then(function() {
				window.location.reload();
			});
		}
	}, label);
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('mode'),
			L.resolveDefault(fs.exec('/usr/sbin/mode', [ 'status' ]), { stdout: '' })
		]);
	},

	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			return fs.exec('/usr/sbin/mode', [ 'apply' ]);
		}).then(function(res) {
			if (res && res.code === 0)
				ui.addNotification(null, E('p', {},
					_('Mode applied. Confirm within the window, or short-press the reset button to roll back.')), 'info');
			else
				ui.addNotification(null, E('p', {},
					_('Mode apply failed: ') + ((res && (res.stderr || res.stdout)) || '')), 'danger');
			window.location.reload();
		});
	},

	render: function(data) {
		var m, s, o;
		var status = (data && data[1] && data[1].stdout) || '';
		var pending = /(^|\s)pending=1(\s|$)/.test(status);
		var remaining = 0;
		var match = status.match(/remaining=(\d+)/);
		if (match)
			remaining = parseInt(match[1], 10);

		var banner = null;
		if (pending) {
			banner = E('div', { 'class': 'cbi-section', 'style': 'border:2px solid #c00;padding:8px;margin-bottom:12px' }, [
				E('h3', {}, _('Mode change pending confirmation')),
				E('p', {}, _('The new mode is active but unconfirmed. It rolls back automatically in about %d seconds unless you keep it.').format(remaining)),
				E('p', {}, _('The red power LED blinks while pending. A short press of the reset button rolls back immediately; a long press still performs a factory reset.')),
				E('div', {}, [
					actionButton(_('Keep changes'), 'apply', 'confirm'),
					' ',
					actionButton(_('Roll back now'), 'remove', 'rollback')
				])
			]);
		}

		m = new form.Map('mode', _('Operation Mode'),
			_('Select how the router connects upstream. Wired router and failover use the WAN jack (lan4, nearest the power connector); failover prefers the wired WAN and falls back to WISP automatically. AP/bridge bridges all ports and disables local DHCP/NAT. Changing modes restarts only the affected services; the access points stay up.'));

		s = m.section(form.NamedSection, 'mode', 'mode', _('Operating mode'));
		s.anonymous = true;
		s.addremove = false;
		o = s.option(form.ListValue, 'selected', _('Mode'));
		o.value('wisp', _('WISP / repeater (Wi-Fi uplink)'));
		o.value('router', _('Wired router (WAN -> NAT)'));
		o.value('ap', _('AP / bridge (dumb AP)'));
		o.value('failover', _('Wired + WISP failover'));
		o.default = 'wisp';

		s = m.section(form.NamedSection, 'wired', 'wired', _('Wired WAN (router / failover)'));
		s.anonymous = true;
		s.addremove = false;
		o = s.option(form.ListValue, 'proto', _('Protocol'));
		o.value('dhcp', 'DHCP');
		o.value('static', _('Static IP'));
		o.default = 'dhcp';
		o = s.option(form.Value, 'ipaddr', _('IP address'));
		o.datatype = 'ip4addr';
		o.depends('proto', 'static');
		o = s.option(form.Value, 'netmask', _('Netmask'));
		o.datatype = 'ip4addr';
		o.depends('proto', 'static');
		o = s.option(form.Value, 'gateway', _('Gateway'));
		o.datatype = 'ip4addr';
		o.depends('proto', 'static');
		o = s.option(form.Value, 'dns', _('DNS servers (space-separated)'));
		o.datatype = 'list(ip4addr)';
		o.depends('proto', 'static');

		s = m.section(form.NamedSection, 'router', 'router', _('Router LAN (router / failover)'));
		s.anonymous = true;
		s.addremove = false;
		s.description = _('Change the LAN subnet if the upstream also uses 192.168.1.0/24.');
		o = s.option(form.Value, 'lan_ip', _('LAN IP address'));
		o.datatype = 'ip4addr';
		o.default = '192.168.1.1';
		o = s.option(form.Value, 'lan_netmask', _('LAN netmask'));
		o.datatype = 'ip4addr';
		o.default = '255.255.255.0';

		s = m.section(form.NamedSection, 'ap', 'ap', _('AP / bridge mode'));
		s.anonymous = true;
		s.addremove = false;
		o = s.option(form.Value, 'mgmt_ip', _('Management IP'));
		o.datatype = 'ip4addr';
		o.default = '192.168.1.1';
		o = s.option(form.Value, 'mgmt_netmask', _('Netmask'));
		o.datatype = 'ip4addr';
		o.default = '255.255.255.0';

		return m.render().then(function(formNode) {
			return E('div', {}, [ banner ? banner : '', formNode ]);
		});
	}
});
