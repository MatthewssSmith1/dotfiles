# Available Behaviors

All names and parameter schemas come from the device. Empty metadata does not prove zero parameters.

| ID | Name | Referenced | Parameter Metadata |
|---|---|---|---|
| 1 | Mouse Key Press | yes | `[{"param1": [{"name": "MB1", "constant": 1}, {"name": "MB2", "constant": 2}, {"name": "MB3", "constant": 4}, {"name": "MB4", "constant": 8}, {"name": "MB5", "constant": 16}], "param2": []}]` |
| 2 | mouse_move | no | `[]` |
| 3 | mouse_scroll | no | `[]` |
| 4 | None | no | `[]` |
| 5 | Bootloader | no | `[]` |
| 6 | Caps Word | no | `[]` |
| 7 | External Power | no | `[]` |
| 8 | Key Press | yes | `[{"param1": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}], "param2": []}]` |
| 9 | Grave/Escape | no | `[]` |
| 10 | Key Repeat | no | `[]` |
| 11 | Key Toggle | no | `[{"param1": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}], "param2": []}]` |
| 12 | Momentary Layer | yes | `[{"param1": [{"name": "Layer", "layer_id": {}}], "param2": []}]` |
| 13 | Layer-Tap | no | `[{"param1": [{"name": "Layer", "layer_id": {}}], "param2": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}]}]` |
| 14 | Mod-Tap | no | `[{"param1": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}], "param2": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}]}]` |
| 15 | Output Selection | no | `[{"param1": [{"name": "Toggle Outputs", "constant": 0}, {"name": "USB Output", "constant": 1}, {"name": "BLE Output", "constant": 2}], "param2": []}]` |
| 16 | Sticky Key | no | `[{"param1": [{"name": "Key", "hid_usage": {"keyboard_max": 255, "consumer_max": 4095}}], "param2": []}]` |
| 17 | Sticky Layer | no | `[{"param1": [{"name": "Layer", "layer_id": {}}], "param2": []}]` |
| 18 | Reset | no | `[]` |
| 19 | To Layer | no | `[{"param1": [{"name": "Layer", "layer_id": {}}], "param2": []}]` |
| 20 | Toggle Layer | no | `[{"param1": [{"name": "Layer", "layer_id": {}}], "param2": []}]` |
| 21 | z_so_off | no | `[]` |
| 22 | Bluetooth | yes | `[{"param1": [{"name": "Next Profile", "constant": 1}, {"name": "Previous Profile", "constant": 2}, {"name": "Clear All Profiles", "constant": 4}, {"name": "Clear Selected Profile", "constant": 0}], "param2": []}, {"param1": [{"name": "Select Profile", "constant": 3}, {"name": "Disconnect Profile", "constant": 5}], "param2": [{"name": "Profile", "range": {"max": 5, "min": 0}}]}]` |
| 23 | Transparent | yes | `[]` |
| 24 | Studio Unlock | yes | `[]` |
