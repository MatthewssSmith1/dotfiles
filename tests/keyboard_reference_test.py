#!/usr/bin/env python3
"""Offline native-to-HTML regression checks; stdlib plus optional installed Node.

Run: python3 -B tests/keyboard_reference_test.py
No browser, device, network, generated files or backend imports are required.
Unknown native codes fail rather than silently accepting a presentation label.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
KEYBOARDS = ROOT / "keyboards"

# Execute the entire actual script, including rendering and event registration.
# This mock tests DOM contracts, not CSS layout or browser accessibility behavior.
DOM_RUNNER = r"""
const vm = require('node:vm');
const assert = require('node:assert/strict');
const fs = require('node:fs');
class Element {
 constructor(tag) {
  this.tag = tag; this.children = []; this.dataset = {}; this.style = {};
  this.attributes = {}; this.listeners = {}; this.value = ''; this.hidden = false;
 }
 append(...items) {
  this.children.push(...items);
  if (this.tag === 'select' && !this.value && items.length) this.value = items[0].value;
 }
 setAttribute(name, value) { this.attributes[name] = value; }
 replaceChildren() { this.children = []; this.value = ''; }
 get options() { return this.children; }
 addEventListener(name, callback) { this.listeners[name] = callback; }
 querySelectorAll(selector) {
  assert.equal(selector, '.card');
  return this.children.filter(child => child.className === 'card');
 }
}
const scripts = JSON.parse(fs.readFileSync(0, 'utf8'));
function run(stored, denied) {
const elements = Object.fromEntries(['maps', 'device', 'layer', 'status', 'print', 'theme']
 .map(id => [id, new Element(['device', 'layer'].includes(id) ? 'select' : 'div')]));
elements.device.value = 'toucan';
let printCalls = 0;
const root = new Element('html');
const writes = [];
const storage = {
 getItem(key) { assert.equal(key, 'keyboard-atlas-theme'); if (denied === 'read') throw Error('denied'); return stored; },
 setItem(key, value) { assert.equal(key, 'keyboard-atlas-theme'); if (denied === 'write') throw Error('denied'); writes.push(value); }
};
const context = vm.createContext({
 document: {documentElement: root, createElement: tag => new Element(tag), getElementById: id => elements[id]},
 get localStorage() { if (denied === 'access') throw Error('denied'); return storage; },
 window: {print: () => printCalls++}
});
new vm.Script(scripts[0]).runInContext(context, {timeout: 5000});
const initial = !['access', 'read'].includes(denied) && stored === 'light' ? 'light' : 'dark';
assert.equal(root.dataset.theme, initial); // Head script resolves theme before rendering.
assert.deepEqual(writes, []); // Only explicit choices are persisted.
new vm.Script(scripts[1]).runInContext(context, {timeout: 5000});
assert.equal(elements.theme.attributes['aria-pressed'], String(initial === 'dark'));
const choices = [initial === 'dark' ? 'light' : 'dark', initial];
for (const theme of choices) {
 elements.theme.listeners.click();
 assert.equal(root.dataset.theme, theme);
 assert.equal(elements.theme.attributes['aria-pressed'], String(theme === 'dark'));
}
assert.deepEqual(writes, ['access', 'write'].includes(denied) ? [] : choices);
const data = vm.runInContext(`Object.fromEntries(Object.entries(devices).map(([id, d]) =>
 [id, {...d, hints: Object.fromEntries(Object.entries(d.layers).map(([layer, keys]) =>
 [layer, keys.map((key, i) => holdHint(id, layer, i, key))]))}]))`, context);
assert.deepEqual(Object.keys(data), ['toucan', 'enhanced', 'plain', 'generic']);
assert.equal(elements.maps.children.length, 4);
assert.equal(elements.layer.value, 'Base');
for (const [id, device] of Object.entries(data)) {
 elements.device.value = id;
 elements.device.listeners.change();
 assert.deepEqual(elements.layer.options.map(o => o.value), ['All layers', ...Object.keys(device.layers)]);
 const visible = elements.maps.children.filter(section => !section.hidden);
 assert.equal(visible.length, 1);
 const section = visible[0];
 assert.equal(section.dataset.device, id);
 assert.equal(section.attributes['aria-label'], device.name);
 for (const option of elements.layer.options) {
  elements.layer.value = option.value;
  elements.layer.listeners.change();
  const cards = section.querySelectorAll('.card').filter(card => !card.hidden);
  assert.equal(cards.length, option.value === 'All layers' ? Object.keys(device.layers).length : 1);
  if (option.value !== 'All layers') assert.equal(cards[0].dataset.layer, option.value);
  assert.equal(elements.status.textContent, `${device.name} / ${option.value}. Intended layout only.`);
 }
 for (const card of section.querySelectorAll('.card')) {
  const layer = card.dataset.layer;
  const scroll = card.children.find(child => child.className === 'scroll');
  assert.equal(scroll.tabIndex, 0);
  assert.equal(scroll.attributes.role, 'region');
  assert.ok(scroll.attributes['aria-label'].includes(layer));
  const board = scroll.children[0];
  assert.equal(board.children.length, device.positions.length);
  const details = card.children.find(child => child.tag === 'details');
  const table = details.children.find(child => child.tag === 'table');
  const rows = table.children.find(child => child.tag === 'tbody').children;
  assert.equal(rows.length, device.positions.length);
  rows.forEach((row, i) => {
   assert.deepEqual(row.children.map(cell => cell.textContent),
    [device.positions[i], device.base[i], device.layers[layer][i], device.hints[layer][i]]);
   const key = board.children[i];
   assert.equal(key.children[0].textContent,
    device.layers[layer][i].replaceAll('-speed', '\nspeed').replaceAll('-light', '\nlight'));
   assert.equal(key.children[1].textContent,
    id === 'toucan' ? `#${i}` : id === 'generic' ? device.positions[i] : `[${device.positions[i]}]`);
   assert.equal(key.children[2]?.textContent || '', device.hints[layer][i]);
  });
 }
}
elements.device.value = 'enhanced'; elements.device.listeners.change();
elements.layer.value = 'Nav'; elements.layer.listeners.change();
elements.device.value = 'plain'; elements.device.listeners.change();
assert.equal(elements.layer.value, 'Base'); // Unreachable Plain Nav must not linger.
elements.print.listeners.click(); assert.equal(printCalls, 1);
return data;
}
for (const stored of [null, 'light', 'dark', '', 'invalid', 'LIGHT']) run(stored);
for (const denied of ['access', 'read', 'write']) run('light', denied);
process.stdout.write(JSON.stringify(run(null)));
"""

QMK = dict(zip(
    "ESC MINS EQL BSPC QUOT BSLS TAB CAPS SCLN ENT LBRC RBRC SLSH COMM DOT "
    "LCTL LGUI SPC DEL LEFT DOWN UP RGHT TRNS NO GRV HOME PGDN PGUP END "
    "LALT LSFT VOLD VOLU BRID BRIU MPRV MPLY MNXT MUTE RALT".split(),
    "Esc - = Backspace ' \\ Tab Caps ; Enter [ ] / , . LCtrl LSuper Space "
    "Delete Left Down Up Right Pass None Grave Home PgDn PgUp End LAlt LShift "
    "Vol- Vol+ Display- Display+ Previous Play/pause Next Mute RAlt".split()))
CUSTOM = dict(zip(
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21],
    "USB RF BLE1 BLE2 BLE3 Mac-task Mac-search Mac-voice Mac-console Mac-DND "
    "Shot-whole Shot-area Side-light+ Side-light- Side-mode Side-color "
    "Side-speed+ Side-speed- Sleep-toggle Battery".split()))
MODS = dict(zip("LGUI LALT LSFT LCTL RCTL RSFT RALT RGUI".split(),
                "LSuper LAlt LShift LCtrl RCtrl RShift RAlt RSuper".split()))
SHIFTED = dict(zip("1234567890", "!@#$%^&*()")) | {
    "GRV": "~", "MINS": "_", "EQL": "+"}
RGB = dict(zip("VAD VAI SPD SPI MOD HUI".split(),
               "RGB-light- RGB-light+ RGB-speed- RGB-speed+ RGB-mode RGB-hue".split()))


def air_binding(code):
    if code.startswith("KC_"):
        key = code[3:]
        if re.fullmatch(r"[A-Z0-9]|F(?:[1-9]|1[0-2])", key):
            return key, ""
        return QMK[key], ""
    if match := re.fullmatch(r"MT\(MOD_(\w+),(KC_\w+)\)", code):
        return air_binding(match[2])[0], "hold " + MODS[match[1]]
    if match := re.fullmatch(r"LT\((\d+),(KC_\w+)\)", code):
        return air_binding(match[2])[0], "hold " + {4: "Nav", 5: "Symbols"}[int(match[1])]
    if match := re.fullmatch(r"MO\((\d+)\)", code):
        return {6: "Functions", 7: "Utilities"}[int(match[1])], "hold layer"
    if match := re.fullmatch(r"LSFT\(KC_(\w+)\)", code):
        return SHIFTED[match[1]], ""
    if match := re.fullmatch(r"CUSTOM\((\d+)\)", code):
        return CUSTOM[int(match[1])], ""
    if code.startswith("RGB_"):
        return RGB[code[4:]], ""
    raise AssertionError(f"Unrecognized VIA code: {code}")


HID = dict(zip(
    [40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56,
     70, 74, 75, 76, 77, 78, 79, 80, 81, 82, *range(224, 232)],
    "Enter Esc Backspace Tab Space - = [ ] \\ ; ' Grave , . / PrintScreen "
    "Home PgUp Delete End PgDn Right Left Down Up LCtrl LShift LAlt LSuper "
    "RCtrl RShift RAlt RSuper".split()))


def zmk_key(value):
    if value in (786666, 786665):
        return {786666: "Vol-", 786665: "Vol+"}[value]
    assert (value >> 16) & 255 == 7, f"Unknown HID page: {value}"
    usage = value & 65535
    if 4 <= usage <= 29:
        key = chr(65 + usage - 4)
    elif 30 <= usage <= 39:
        key = str((usage - 29) % 10)
    elif 58 <= usage <= 69:
        key = f"F{usage - 57}"
    else:
        key = HID[usage]
    if value >> 24:
        assert value >> 24 == 2, f"Unknown HID modifiers: {value}"
        key = (SHIFTED | {"Grave": "~", "-": "_", "=": "+",
                          "RCtrl": "LShift+RCtrl"})[key]
    return key


def toucan_binding(binding):
    behavior, p1, p2 = (binding[k] for k in ("behavior_id", "param1", "param2"))
    if behavior == 8:
        return zmk_key(p1), ""
    if behavior == 14:
        return zmk_key(p2), "hold " + zmk_key(p1)
    if behavior == 12:
        if p1 == 458795:
            return "Anomaly", ""
        return {1: "Nav", 2: "Symbols"}[p1], "hold layer"
    if behavior == 22:
        return ({0: "BLE1", 1: "BLE2", 2: "BLE3"}[p2] if p1 == 3
                else {0: "Clear", 2: "BTprev", 1: "BTnext"}[p1]), ""
    if behavior == 15:
        return {1: "USB", 2: "BLE"}[p1], ""
    if behavior == 1:
        return {2: "MouseRight", 16: "Mouse5", 8: "Mouse4"}[p1], ""
    assert p1 == p2 == 0, binding
    return {23: "Pass", 4: "None", 24: "StudioUnlock", 0: "Unknown0"}[behavior], ""


KEYD = dict(zip(
    "leftbrace rightbrace backslash semicolon slash comma dot esc capslock "
    "backspace delete noop equal enter home pagedown pageup end left down up "
    "right volumedown volumeup grave tab apostrophe minus space leftcontrol "
    "rightcontrol leftmeta rightmeta leftalt rightalt leftshift rightshift menu".split(),
    "[ ] \\ ; / , . Esc Caps Backspace Delete None = Enter Home PgDn PgUp End "
    "Left Down Up Right Vol- Vol+ Grave Tab ' - Space LCtrl RCtrl LSuper RSuper "
    "LAlt RAlt LShift RShift Menu".split()))


def keyd_binding(code):
    hint = ""
    if match := re.fullmatch(r"overloadt\((\w+), (\w+), (\d+)\)", code):
        modifier = {"meta": "Super", "alt": "Alt", "shift": "Shift",
                    "control": "Ctrl", "nav": "Nav", "symbols": "Symbols"}[match[1]]
        hint = "hold " + modifier
        assert int(match[3]) == (180 if modifier == "Shift" else 200)
        code = match[2]
    if re.fullmatch(r"[a-z0-9]|f(?:[1-9]|1[0-2])|[!@#$%^&*()_+~-]", code):
        return code.upper(), hint
    return KEYD[code], hint


class ReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        node = shutil.which("node")
        if not node:
            raise unittest.SkipTest("Node unavailable: HTML JavaScript/native presentation checks skipped")
        html = (KEYBOARDS / "reference.html").read_text()
        scripts = re.findall(r"<script>([\s\S]*?)</script>", html)
        if len(scripts) != 2:
            raise AssertionError("Expected inline theme bootstrap and map scripts")
        cls.html = html
        result = subprocess.run([node, "-e", DOM_RUNNER], input=json.dumps(scripts),
                                text=True, capture_output=True, timeout=20, cwd=ROOT)
        if result.returncode:
            raise AssertionError(f"HTML JS syntax/render/selector failure:\n{result.stderr}")
        cls.devices = json.loads(result.stdout)

    def test_air60_all_448_positions_and_enhanced_hints(self):
        native = json.loads((KEYBOARDS / "air60/layout.json").read_text())["layers"]
        device = self.devices["enhanced"]
        self.assertEqual(len(device["positions"]), 64)
        self.assertEqual(len(set(device["positions"])), 64)
        self.assertEqual(device["ids"], {"Base": 0, "Nav": 4, "Symbols": 5,
                                       "Functions": 6, "Utilities": 7,
                                       "Retired 1": 1, "Retired 2": 2})
        self.assertEqual(len(device["layers"]), 7)
        for name, layer in device["ids"].items():
            for i, position in enumerate(device["positions"]):
                r, c = map(int, position.split(","))
                with self.subTest(layer=name, position=position):
                    output, hint = air_binding(native[layer][r * 17 + c])
                    self.assertEqual(device["layers"][name][i], output)
                    self.assertEqual(device["hints"][name][i], hint)

    def test_air60_plain_and_via_geometry(self):
        plain, enhanced = self.devices["plain"], self.devices["enhanced"]
        self.assertEqual(plain["ids"], {"Base": 3, "Functions": 6, "Utilities": 7,
                                      "Retired 1": 1, "Retired 2": 2})
        native = json.loads((KEYBOARDS / "air60/layout.json").read_text())["layers"]
        for name, layer in plain["ids"].items():
            for i, position in enumerate(plain["positions"]):
                r, c = map(int, position.split(","))
                self.assertEqual((plain["layers"][name][i], plain["hints"][name][i]),
                                 air_binding(native[layer][r * 17 + c]))
        definition = json.loads((KEYBOARDS / "snapshots/air60/via-definition.json").read_text())
        positions, geometry = [], []
        for y, row in enumerate(definition["layouts"]["keymap"]):
            x, width = 0, 1
            for entry in row:
                if isinstance(entry, dict):
                    self.assertEqual(set(entry), {"w"})
                    width = entry["w"]
                else:
                    positions.append(entry)
                    geometry.append({"x": x, "y": y, "w": width})
                    x += width
                    width = 1
        for device in (plain, enhanced):
            self.assertEqual(device["positions"], positions)
            self.assertEqual(device["geometry"], geometry)
            self.assertEqual(device["base"], device["layers"]["Base"])
        self.assertNotEqual(plain["base"], enhanced["base"])
        self.assertIn("Mac switch / base 0", enhanced["note"])
        self.assertIn("Windows switch / base 3", plain["note"])

    def test_toucan_all_168_bindings_hints_and_geometry(self):
        device = self.devices["toucan"]
        native = json.loads((KEYBOARDS / "toucan/keymap.json").read_text())
        self.assertEqual(device["positions"], list(map(str, range(42))))
        self.assertEqual(device["ids"], {"Base": 0, "Nav": 1, "Symbols": 2, "Functions": 3})
        self.assertEqual(len(native["layers"]), 4)
        for layer in native["layers"]:
            name = layer["name"]
            self.assertEqual(len(layer["bindings"]), 42)
            self.assertEqual(device["ids"][name], layer["id"])
            for i, binding in enumerate(layer["bindings"]):
                with self.subTest(layer=name, position=i):
                    self.assertEqual((device["layers"][name][i], device["hints"][name][i]),
                                     toucan_binding(binding))
        snapshot = json.loads((KEYBOARDS / "snapshots/toucan/snapshot.json").read_text())
        for actual, key in zip(device["geometry"], snapshot["physical_layouts"]["layouts"][0]["keys"]):
            for prop in ("x", "y", "r"):
                self.assertAlmostEqual(actual.get(prop, 0), key[prop] / 100)
            self.assertEqual(actual["w"], key["width"] / 100)
            if key["r"]:
                for prop in ("rx", "ry"):
                    self.assertAlmostEqual(actual[prop], key[prop] / 100)

    def test_generic_native_layers_and_all_hints(self):
        sections = {}
        # Match native include order; later main assignments replace earlier ones.
        for filename in ("home-row-mods", "shared-layers", "default.conf"):
            section = None
            for line in (KEYBOARDS / "keyd" / filename).read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("["):
                    section = line[1:-1]
                    sections.setdefault(section, {})
                elif " = " in line:
                    key, code = line.split(" = ", 1)
                    sections[section][key] = code
        device = self.devices["generic"]
        self.assertEqual(len(device["positions"]), 66)
        self.assertEqual(len(set(device["positions"])), 66)
        self.assertEqual(set(device["layers"]), {"Base", "Nav", "Symbols"})
        for name, section in (("Base", "main"), ("Nav", "nav"), ("Symbols", "symbols")):
            self.assertFalse(set(sections[section]) - set(device["positions"]))
            for i, position in enumerate(device["positions"]):
                with self.subTest(layer=name, position=position):
                    code = sections[section].get(position)
                    expected = keyd_binding(code or position) if name == "Base" or code else ("Pass", "")
                    self.assertEqual((device["layers"][name][i], device["hints"][name][i]), expected)

    def test_full_js_rendering_and_selectors(self):
        # setUpClass executes syntax, DOM tables/labels/hints, all selector choices,
        # inaccessible Plain Nav fallback, visibility, status and print assertions.
        self.assertEqual(set(self.devices), {"toucan", "enhanced", "plain", "generic"})

    def test_theme_bootstrap_control_and_print_palette(self):
        self.assertLess(self.html.index('<script>'), self.html.index('<style>'))
        self.assertIn('<button id="theme" type="button" aria-label="Dark theme" aria-pressed="true">Dark theme</button>', self.html)
        self.assertIn('#theme[aria-pressed="true"]::after{content:" / on"}', self.html)
        self.assertIn('#theme[aria-pressed="false"]::after{content:" / off"}', self.html)
        self.assertIn('button:focus-visible', self.html)
        css = re.search(r'<style>(.*?)</style>', self.html, re.S)[1]
        light = re.search(r':root\{([^}]+)\}', css)[1]
        for declaration in ('color-scheme:light', '--paper:#f3f0e7', '--ink:#20342f',
                            '--control:#fffdf7', '--card:#faf9f3', '--key:#fff',
                            '--hint:#315b35', '--green:#dce9d7', '--warn:#f7dfcf'):
            self.assertIn(declaration + ';', light + ';')
        # Dark variables apply only to screens; print inherits the original palette.
        self.assertRegex(css, r'@media screen\{:root:not\(\[data-theme="light"\]\)\{color-scheme:dark;[^}]+\}\}')
        self.assertEqual(css.count('color-scheme:dark'), 1)
        print_css = css.split('@media print{', 1)[1]
        self.assertIn('body{background:white;', print_css)
        self.assertIn('.controls,.screen-only,details{display:none!important}', print_css)


if __name__ == "__main__":
    unittest.main(verbosity=2)
