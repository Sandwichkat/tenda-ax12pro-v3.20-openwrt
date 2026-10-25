'use strict';
'require view';
'require form';
'require uci';
'require poll';
'require dom';
'require wisp_status';

return view.extend({
	load: function() {
		return wisp_status.load();
	},

	render: function(data) {
		var m, s, o;

		// Keep the status block live: clients associate after the page has
		// loaded, so refresh it every poll interval (the status page include
		// already polls; this view previously rendered only once).
		var statusBody = E('div', {}, wisp_status.render(data));
		var status = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Wi-Fi status'),
			statusBody
		]);

		poll.add(function() {
			return wisp_status.load().then(function(d) {
				dom.content(statusBody, wisp_status.render(d));
			});
		});

		m = new form.Map('wisp', _('Wireless'),
			_('Upstream station (wlan0) and access points (5 GHz wlan1, 2.4 GHz wlan2). ' +
			  'Save & Apply restarts the APs with the new settings; upstream changes take effect on reboot.'));

		s = m.section(form.NamedSection, 'uplink', 'uplink', _('Upstream Wi-Fi (STA)'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'ssid', _('Upstream SSID'));
		o.datatype = 'maxlength(32)';
		o.rmempty = false;

		o = s.option(form.Value, 'psk', _('Upstream password'));
		o.password = true;
		o.datatype = 'maxlength(63)';

		o = s.option(form.Value, 'fallback_ssid', _('Fallback SSID'));
		o.datatype = 'maxlength(32)';
		o.optional = true;

		o = s.option(form.Value, 'fallback_psk', _('Fallback password'));
		o.password = true;
		o.datatype = 'maxlength(63)';
		o.optional = true;

		s = m.section(form.NamedSection, 'ap', 'ap', _('Access Points (5 GHz + 2.4 GHz)'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'ssid', _('AP SSID'));
		o.datatype = 'maxlength(32)';
		o.rmempty = false;

		o = s.option(form.Value, 'psk', _('AP password'));
		o.password = true;
		o.datatype = 'minlength(8) maxlength(63)';
		o.rmempty = false;

		o = s.option(form.ListValue, 'channel', _('Channel'));
		o.value('149', '149 (5745 MHz)');
		o.value('153', '153 (5765 MHz)');
		o.value('157', '157 (5785 MHz)');
		o.value('161', '161 (5805 MHz)');
		o.default = '149';

		o = s.option(form.ListValue, 'width', _('Channel width'));
		o.value('80', '80 MHz');
		o.value('40', '40 MHz');
		o.value('20', '20 MHz');
		o.default = '80';

		o = s.option(form.ListValue, 'channel2g', _('2.4 GHz channel (router/AP modes)'),
			_('Used when the uplink STA does not provide a channel (wired router / AP-bridge). WISP and failover follow the uplink.'));
		o.value('1', '1 (2412 MHz)');
		o.value('6', '6 (2437 MHz)');
		o.value('11', '11 (2462 MHz)');
		o.default = '11';

		o = s.option(form.ListValue, 'txpower', _('TX power (dBm)'),
			_('30 dBm is the maximum this driver accepts; the board calibration caps the actual PA near 25 dBm.'));
		o.value('30', '30 dBm (maximum)');
		o.value('25', '25 dBm');
		o.value('20', '20 dBm');
		o.value('15', '15 dBm');
		o.value('10', '10 dBm');
		o.value('5', '5 dBm');
		o.default = '30';

		o = s.option(form.Flag, 'band2g', _('Enable 2.4 GHz AP'),
			_('Second BSS on the uplink STA channel with the same SSID and password (better range).'));
		o.default = '1';
		o.rmempty = false;

		return m.render().then(function(formNode) {
			return E('div', {}, [ status, formNode ]);
		});
	}
});
