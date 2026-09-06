#!/usr/bin/env python3
"""Reproducible, offline migration of the original native VIA export.

Only --write updates the generated layout.json; never opens a device.
The checked-in native layout.json, not this script, is the apply input.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def desired_layout():
    raw = (HERE.parent / "snapshots/air60/original.layout.json").read_bytes()
    if hashlib.sha256(raw).hexdigest() != "2b2460e9fc53981fc31c27f54faee67eca979ba415c68c7e0762bc4334cd1109":
        raise ValueError("Original export hash mismatch")
    original = json.loads(raw)
    result = copy.deepcopy(original)
    # Keep the original physical lookup unchanged until all overlays are built.
    plain = result["layers"][0].copy()
    for i, key in enumerate(plain):
        if key.startswith("MT("):
            plain[i] = re.search(r",(KC_[A-Z]+)\)", key)[1]
        elif key.startswith("MO("):
            plain[i] = "MO(6)"
    enhanced = plain.copy()
    for key, mod in zip("ASDFHJKL", ("LGUI", "LALT", "LSFT", "LCTL", "RCTL", "RSFT", "RALT", "RGUI")):
        enhanced[plain.index("KC_" + key)] = f"MT(MOD_{mod},KC_{key})"
    for key in "Z X C V B SLSH N M COMM DOT".split():
        layer = 4 if key in "Z X C V B".split() else 5
        enhanced[plain.index("KC_" + key)] = f"LT({layer},KC_{key})"
    result["layers"][0] = enhanced
    # Nonexistent matrix positions stay KC_NO; every physical position falls through.
    overlay = ["KC_NO" if key == "KC_NO" else "KC_TRNS" for key in plain]
    result["layers"][1] = overlay.copy()
    result["layers"][2] = overlay.copy()
    for layer in (4, 5, 6, 7):
        result["layers"][layer] = overlay.copy()

    def bind(layer, key, value):
        result["layers"][layer][plain.index("KC_" + key)] = value

    for key, value in zip("Y U I O H J K L N M COMM DOT".split(),
                          "HOME PGDN PGUP END LEFT DOWN UP RGHT NO VOLD VOLU NO".split()):
        bind(4, key, "KC_" + value)
    for key, mod in zip("ASDF", ("LGUI", "LALT", "LSFT", "LCTL")):
        bind(4, key, "KC_" + mod)
    bind(4, "QUOT", "KC_GRV")

    for key, digit in zip("A S D F G SCLN H J K L".split(), "1234567890"):
        bind(5, key, "KC_" + digit)
    for key, digit in zip("Q W E R T BSLS Y U I O".split(), "1234567890"):
        bind(5, key, "LSFT(KC_" + digit + ")")
    for key, value in zip("N M COMM DOT".split(), ("LSFT(KC_MINS)", "KC_MINS", "LSFT(KC_EQL)", "KC_EQL")):
        bind(5, key, value)
    bind(5, "QUOT", "KC_GRV")
    result["layers"][5][0] = "LSFT(KC_GRV)"
    result["layers"][5][4 * 17] = "LSFT(KC_GRV)"  # Physical left Shift, matching Toucan.

    for n, key in enumerate("A S D F G SCLN H J K L P BSLS".split(), 1):
        # F12 uses the *rightmost* backslash, not the moved digit-6 position.
        i = 2 * 17 + 13 if n == 12 else plain.index("KC_" + key)
        result["layers"][6][i] = f"KC_F{n}"
    for n in range(12):
        result["layers"][6][17 + 1 + n] = f"KC_F{n + 1}"
    for key, code in zip("Q W E R T O".split(), (3, 4, 5, 2, 1, 21)):
        bind(6, key, f"CUSTOM({code})")
    bind(6, "QUOT", "KC_GRV")
    result["layers"][6][0] = "LSFT(KC_GRV)"
    for key, code in {"N": "RGB_SPD", "M": "RGB_SPI", "LBRC": "RGB_VAD",
                      "RBRC": "RGB_VAI", "DOWN": "RGB_MOD", "UP": "RGB_VAD",
                      "RGHT": "RGB_HUI", "SLSH": "MO(7)"}.items():
        bind(6, key, code)

    # Fn + slash retains side-light controls on original matrix positions.
    for i, code in enumerate(original["layers"][6]):
        if code.startswith("CUSTOM("):
            result["layers"][7][i] = code
    for i, code in enumerate(original["layers"][1]):
        if i // 17 == 1 and code not in ("KC_NO", "KC_TRNS"):
            result["layers"][7][i] = code
    for key, code in zip("Q W E R T O P".split(), (6, 7, 8, 9, 10, 20, 21)):
        bind(7, key, f"CUSTOM({code})")
    bind(7, "I", "CUSTOM(11)")
    bind(7, "U", "CUSTOM(12)")
    # Vendor switch policy: Mac = 0 (NKRO off), Windows = 3 (NKRO on).
    for (row, col), key in {
        (2, 0): "TAB", (3, 0): "CAPS", (4, 0): "LSFT",
        (5, 2): "LALT", (5, 9): "RALT", (2, 6): "QUOT",
        (3, 6): "DEL", (4, 7): "LBRC",
    }.items():
        plain[row * 17 + col] = "KC_" + key
    result["layers"][3] = plain
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    layout = desired_layout()
    if args.write:
        (HERE / "layout.json").write_text(json.dumps(layout, indent=2) + "\n")
    else:
        print(json.dumps(layout, indent=2))


if __name__ == "__main__":
    main()
