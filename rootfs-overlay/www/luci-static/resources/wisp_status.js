'use strict';
'require baseclass';
'require rpc';
'require uci';

var callIwinfoInfo = rpc.declare({
	object: 'iwinfo', method: 'info', params: [ 'device' ], expect: {}
});
var callIwinfoAssoc = rpc.declare({
	object: 'iwinfo', method: 'assoclist', params: [ 'device' ], expect: { results: [] }
});
var callHapd5 = rpc.declare({
	object: 'hostapd.wlan1', method: 'get_status', expect: {}
});
var callHapd2 = rpc.declare({
	object: 'hostapd.wlan2', method: 'get_status', expect: {}
});

function channelText(info) {
	if (!info || !info.channel)
		return '-';
	return '%d (%.3f GHz)'.format(info.channel, (info.frequency || 0) / 1000);
}

function widthText(info) {
	if (!info || !info.channel)
		return '-';
	var center = info.center_chan1 || info.channel;
	var d = Math.abs(center - info.channel);
	if (d == 0) return '20 MHz';
	if (d <= 2) return '40 MHz';
	if (d <= 6) return '80 MHz';
	return '160 MHz';
}

function rateText(rt) {
	if (!rt || typeof(rt.rate) != 'number')
		return '-';
	return '%.1f Mbit/s'.format(rt.rate / 1000);
}

/*
 * rpc.declare() with `expect: { results: [] }` unwraps the `results` key, so
 * callIwinfoAssoc() resolves to the station array itself, not an object with
 * a .results member.  Accept both shapes here (the raw ubus reply has been
 * seen in the wild too).
 */
function assocList(assoc) {
	if (Array.isArray(assoc))
		return assoc;
	return (assoc && assoc.results) || [];
}

function clientTable(assoc) {
	var list = assocList(assoc);
	var rows = [];
	for (var i = 0; i < list.length; i++) {
		var sta = list[i];
		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, sta.mac || '?'),
			E('td', { 'class': 'td' }, (typeof(sta.signal) == 'number') ? '%d dBm'.format(sta.signal) : '-'),
			E('td', { 'class': 'td' }, rateText(sta.rx)),
			E('td', { 'class': 'td' }, rateText(sta.tx))
		]));
	}
	if (!rows.length)
		rows.push(E('tr', { 'class': 'tr placeholder' }, [
			E('td', { 'class': 'td', 'colspan': '4' }, E('em', {}, 'No clients connected'))
		]));
	return E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, 'Client'),
			E('th', { 'class': 'th' }, 'Signal'),
			E('th', { 'class': 'th' }, 'RX rate'),
			E('th', { 'class': 'th' }, 'TX rate')
		])
	].concat(rows));
}

function apBox(title, info, assoc, hapd) {
	var ssid = (hapd && hapd.ssid) || uci.get('wisp', 'ap', 'ssid') || '-';
	var count = assocList(assoc).length;
	return E('div', { 'class': 'ifacebox', 'style': 'margin-bottom:12px' }, [
		E('div', { 'class': 'ifacebox-head center active' }, E('strong', {}, title)),
		E('div', { 'class': 'ifacebox-body left' }, [
			E('div', {}, [
				E('span', {}, [ 'SSID: ', E('strong', {}, ssid) ]), ' | ',
				E('span', {}, [ 'BSSID: ', (info && info.bssid) || '-' ]), ' | ',
				E('span', {}, [ 'Channel: ', channelText(info), ', ', widthText(info) ]), ' | ',
				E('span', {}, [ 'TX power: ', (info && typeof(info.txpower) == 'number') ? '%d dBm'.format(info.txpower) : '-' ]), ' | ',
				E('span', {}, [ 'Clients: ', '%d'.format(count) ])
			]),
			clientTable(assoc)
		])
	]);
}

function uplinkBox(info) {
	return E('div', { 'class': 'ifacebox', 'style': 'margin-bottom:12px' }, [
		E('div', { 'class': 'ifacebox-head center active' }, E('strong', {}, 'Uplink (WISP STA)')),
		E('div', { 'class': 'ifacebox-body left' }, [
			E('span', {}, [ 'SSID: ', E('strong', {}, (info && info.ssid) || '-') ]), ' | ',
			E('span', {}, [ 'BSSID: ', (info && info.bssid) || '-' ]), ' | ',
			E('span', {}, [ 'Channel: ', channelText(info) ]), ' | ',
			E('span', {}, [ 'Signal: ', (info && typeof(info.signal) == 'number') ? '%d dBm'.format(info.signal) : '-' ]), ' | ',
			E('span', {}, [ 'Rate: ', (info && typeof(info.bitrate) == 'number') ? '%.1f Mbit/s'.format(info.bitrate / 1000) : '-' ])
		])
	]);
}

return baseclass.extend({
	load: function() {
		return Promise.all([
			uci.load('wisp'),
			L.resolveDefault(callIwinfoInfo('wlan0'), null),
			L.resolveDefault(callIwinfoInfo('wlan1'), null),
			L.resolveDefault(callIwinfoAssoc('wlan1'), { results: [] }),
			L.resolveDefault(callIwinfoInfo('wlan2'), null),
			L.resolveDefault(callIwinfoAssoc('wlan2'), { results: [] }),
			L.resolveDefault(callHapd5(), null),
			L.resolveDefault(callHapd2(), null)
		]);
	},

	render: function(data) {
		data = data || [];
		var uplink = data[1], i5 = data[2], a5 = data[3], i2 = data[4], a2 = data[5];
		var h5 = data[6], h2 = data[7];
		var boxes = [
			uplinkBox(uplink),
			apBox('5 GHz access point', i5, a5, h5)
		];

		if (uci.get('wisp', 'ap', 'band2g') != '0')
			boxes.push(apBox('2.4 GHz access point', i2, a2, h2));

		return E('div', {}, boxes);
	}
});
