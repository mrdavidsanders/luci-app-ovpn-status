#!/usr/bin/env node
/*
 * Unit test for the data-transformation logic in the JS view.
 *
 * The LuCI view (index.js) uses LuCI-specific globals (view, dom, fs, ui, _).
 * We stub those just enough to load the module in plain Node, then exercise
 * the pure functions (humanBytes, splitAddrs) and the clientRow() builder to
 * confirm the table rows are produced correctly from the sample JSON.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

// --- Minimal LuCI stubs -------------------------------------------------

// A tiny DOM element that records its tag, attributes and children.
function El(tag, attrs, children) {
	this.tag = tag;
	this.attrs = attrs || {};
	this.children = (children || []).map(function (c) {
		return (typeof c === 'string') ? c : c;
	});
}
El.prototype.textContent = function () {
	return this.children.map(function (c) {
		return (typeof c === 'string') ? c : c.textContent();
	}).join('');
};

const E = function (tag, attrs, children) {
	return new El(tag, attrs, children);
};

// The LuCI translation helper: identity.
const _ = function (s) { return s; };

const view = {
	extend: function (def) {
		const self = {};
		Object.assign(self, def);
		view.__lastResult = self;
		return self;
	}
};

const dom = {};
const fsStub = {};
const ui = {};
const tools = { widgets: {} };

// Stub of the LuCI uci module. The view's refreshIntervalMs() reads
// openvpn_status.main.interval from it; tests can override the value.
const uciStub = {
	__value: null,
	get: function (cfg, section, option) {
		return uciStub.__value;
	}
};

// --- Load the view module ----------------------------------------------

const viewPath = path.join(__dirname, '..', 'htdocs', 'luci-static', 'resources', 'view', 'openvpn_status', 'index.js');
let code = fs.readFileSync(viewPath, 'utf8');

// LuCI loads views as modules (wrapped in a function) so a top-level
// `return` is legal. Plain Node's vm does not do that, so wrap it ourselves.
code = '(function(){\n' + code + '\n})()';

const sandbox = {
	E, _, view, dom, fs: fsStub, ui, tools, uci: uciStub,
	JSON, console,
	setInterval: function () { return 0; }
};
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: viewPath });

// The module returns a view.extend(...) instance.
const viewInstance = sandbox.view.__lastResult;
const humanBytes = viewInstance.humanBytes;
const splitAddrs = viewInstance.splitAddrs;
const clientRow = viewInstance.clientRow;
const refreshIntervalMs = viewInstance.refreshIntervalMs;

// --- Tests --------------------------------------------------------------

let passed = 0;
function ok(cond, msg) {
	assert.ok(cond, msg);
	passed++;
	console.log('  ok - ' + msg);
}

console.log('humanBytes()');
ok(humanBytes(0) === '0 B', '0 -> "0 B"');
ok(humanBytes(1023) === '1023 B', '1023 -> "1023 B"');
ok(humanBytes(1024) === '1.00 KB', '1024 -> "1.00 KB"');
ok(humanBytes(16012576) === '15 MB', '16012576 -> "15 MB"');
ok(humanBytes(26567043) === '25 MB', '26567043 -> "25 MB"');
ok(humanBytes(192474864) === '184 MB', '192474864 -> "184 MB"');
ok(humanBytes(4468886754) === '4.16 GB', '4468886754 -> "4.16 GB"');

console.log('splitAddrs()');
let s = splitAddrs(['192.8.0.5', 'aa:42:42:42:42::5']);
ok(s[0] === '192.8.0.5' && s[1] === 'aa:42:42:42:42::5', 'splits v4 and v6');
s = splitAddrs(['10.0.0.1']);
ok(s[0] === '10.0.0.1' && s[1] === '', 'v4 only');
s = splitAddrs(['fd00::1']);
ok(s[0] === '' && s[1] === 'fd00::1', 'v6 only');
s = splitAddrs([]);
ok(s[0] === '' && s[1] === '', 'empty list');

console.log('clientRow()');
const sample = JSON.parse(fs.readFileSync(path.join(__dirname, 'openvpn_test.json'), 'utf8'));
const row = clientRow(sample[0]);
ok(row.tag === 'tr', 'row is a <tr>');
ok(row.children.length === 6, 'row has 6 cells');
ok(row.children[0].textContent() === 'test-phone', 'cell 0 = Common Name');
ok(row.children[1].textContent() === '192.8.0.5 / aa:42:42:42:42::5', 'cell 1 = v4 / v6');
ok(row.children[2].textContent() === '10.10.0.254:37440', 'cell 2 = Real Address');
ok(row.children[3].textContent() === '15 MB / 25 MB', 'cell 3 = RX / TX');
ok(row.children[4].textContent() === '2026-08-21T16:06:46', 'cell 4 = Connected Since');
ok(row.children[5].textContent() === '2026-08-22T02:25:07', 'cell 5 = Last Ref');

// XSS safety: a hostile Common Name must be treated as text, and the row
// must still be well-formed (no injection into the structure).
const evil = clientRow({ 'Common Name': '<img src=x onerror=alert(1)>', 'Real Address': '1.2.3.4:5', 'Connected Since': 'x', 'Last Ref': 'y', 'Bytes Received': 0, 'Bytes Sent': 0, 'Virtual Address': ['10.0.0.1'] });
ok(evil.children[0].children[0] === '<img src=x onerror=alert(1)>', 'hostile CN kept as a text node (escaped by LuCI at render time)');
ok(evil.children.length === 6, 'hostile CN does not break row structure');

console.log('refreshIntervalMs()');
uciStub.__value = null;
ok(refreshIntervalMs() === 60000, 'unset config falls back to 60s');
uciStub.__value = '120';
ok(refreshIntervalMs() === 120000, 'UCI value 120 -> 120000 ms');
uciStub.__value = '5';
ok(refreshIntervalMs() === 5000, 'UCI value 5 -> 5000 ms');
uciStub.__value = '1';
ok(refreshIntervalMs() === 5000, 'values below the 5s minimum are clamped');
uciStub.__value = 'garbage';
ok(refreshIntervalMs() === 60000, 'non-numeric value falls back to 60s');

console.log('\nAll ' + passed + ' assertions passed.');
