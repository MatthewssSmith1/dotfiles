"""Small ZMK Studio protobuf codec; wire contract provenance in README.md."""
import base64

# Fields: name, protobuf kind (u/int/sint/bool/str/bytes/message), repeated, oneof.
SCHEMA = {}


def schema(name, fields):
    SCHEMA[name] = {i: (n, t, r, o) for i, n, t, r, o in fields}


def fields(name, spec):
    schema(name, [(i, n.rstrip('*!'), t, n.endswith('*'), n.endswith('!'))
                  for i, n, t in spec])


fields('Request', [(1,'request_id','u'), (3,'core!','CoreRequest'),
                   (4,'behaviors!','BehaviorsRequest'), (5,'keymap!','KeymapRequest')])
fields('CoreRequest', [(1,'get_device_info!','bool'), (2,'get_lock_state!','bool')])
fields('BehaviorsRequest', [(1,'list_all_behaviors!','bool'), (2,'get_behavior_details!','DetailsRequest')])
fields('DetailsRequest', [(1,'behavior_id','u')])
fields('KeymapRequest', [(1,'get_keymap!','bool'), (2,'set_layer_binding!','SetBinding'),
                        (3,'check_unsaved_changes!','bool'), (4,'save_changes!','bool'),
                        (6,'get_physical_layouts!','bool'), (12,'set_layer_props!','SetProps')])
fields('SetBinding', [(1,'layer_id','u'), (2,'key_position','int'), (3,'binding','Binding')])
fields('SetProps', [(1,'layer_id','u'), (2,'name','str')])
fields('Binding', [(1,'behavior_id','sint'), (2,'param1','u'), (3,'param2','u')])
fields('Response', [(1,'request_response!','RequestResponse'), (2,'notification!','Notification')])
fields('RequestResponse', [(1,'request_id','u'), (2,'meta!','Meta'), (3,'core!','CoreResponse'),
                         (4,'behaviors!','BehaviorsResponse'), (5,'keymap!','KeymapResponse')])
fields('Meta', [(1,'no_response!','bool'), (2,'simple_error!','u')])
fields('CoreResponse', [(1,'get_device_info!','DeviceInfo'), (2,'get_lock_state!','u')])
fields('DeviceInfo', [(1,'name','str'), (2,'serial_number','bytes')])
fields('BehaviorsResponse', [(1,'list_all_behaviors!','BehaviorList'), (2,'get_behavior_details!','Details')])
fields('BehaviorList', [(1,'behaviors*','u')])
fields('Details', [(1,'id','u'), (2,'display_name','str'), (3,'metadata*','ParameterSet')])
fields('ParameterSet', [(1,'param1*','Parameter'), (2,'param2*','Parameter')])
fields('Parameter', [(1,'name','str'), (2,'nil!','Empty'), (3,'constant!','u'),
                     (4,'range!','Range'), (5,'hid_usage!','Hid'), (6,'layer_id!','Empty')])
fields('Empty', [])
fields('Range', [(1,'min','int'), (2,'max','int')])
fields('Hid', [(1,'keyboard_max','u'), (2,'consumer_max','u')])
fields('KeymapResponse', [(1,'get_keymap!','Keymap'), (2,'set_layer_binding!','u'),
                         (3,'check_unsaved_changes!','bool'), (4,'save_changes!','Save'),
                         (6,'get_physical_layouts!','Layouts'), (12,'set_layer_props!','u')])
fields('Keymap', [(1,'layers*','Layer'), (2,'available_layers','u'), (3,'max_layer_name_length','u')])
fields('Layer', [(1,'id','u'), (2,'name','str'), (3,'bindings*','Binding')])
fields('Save', [(1,'ok!','bool'), (2,'err!','u')])
fields('Layouts', [(1,'active_layout_index','u'), (2,'layouts*','Layout')])
fields('Layout', [(1,'name','str'), (2,'keys*','Geometry')])
fields('Geometry', [(i, n, 'sint') for i,n in enumerate(('width','height','x','y','r','rx','ry'),1)])
fields('Notification', [(2,'core!','CoreNotification'), (5,'keymap!','KeymapNotification')])
fields('CoreNotification', [(1,'lock_state_changed!','u')])
fields('KeymapNotification', [(1,'unsaved_changes_status_changed!','bool')])


def varint(value):
    if not 0 <= value < 1 << 64:
        raise ValueError('varint out of range')
    out = bytearray()
    while value > 127:
        out.append((value & 127) | 128)
        value >>= 7
    return bytes(out + bytes([value]))


def take(data, offset):
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise ValueError('truncated varint')
        b = data[offset]
        offset += 1
        value |= (b & 127) << shift
        if not b & 128:
            if value >= 1 << 64:
                raise ValueError('oversized varint')
            return value, offset
    raise ValueError('oversized varint')


def encode(name, obj):
    known = {f[0] for f in SCHEMA[name].values()}
    if set(obj) - known:
        raise ValueError('unknown protobuf fields')
    out = b''
    for number, (key, kind, repeated, _) in SCHEMA[name].items():
        if key not in obj:
            continue
        for value in obj[key] if repeated else [obj[key]]:
            if kind in ('u','int','sint','bool'):
                value = (value << 1) ^ (value >> 31) if kind == 'sint' else int(value)
                out += varint(number << 3) + varint(value & ((1 << 64)-1))
            else:
                value = (value.encode() if kind == 'str' else base64.b64decode(value)
                         if kind == 'bytes' else encode(kind, value))
                out += varint(number << 3 | 2) + varint(len(value)) + value
    return out


def decode(name, data):
    spec = SCHEMA[name]
    out = {key: ([] if repeated else '' if kind in ('str','bytes') else False if kind == 'bool' else 0)
           for key,kind,repeated,oneof in spec.values() if repeated or (not oneof and kind not in SCHEMA)}
    offset = 0
    while offset < len(data):
        tag, offset = take(data, offset)
        number, wire = tag >> 3, tag & 7
        if not number:
            raise ValueError('invalid protobuf tag')
        if wire == 0:
            raw, offset = take(data, offset)
        elif wire in (1,2,5):
            if wire == 2:
                size, offset = take(data, offset)
            else:
                size = 8 if wire == 1 else 4
            raw = data[offset:offset+size]
            offset += size
            if len(raw) != size:
                raise ValueError('truncated field')
        else:
            raise ValueError('unsupported wire type')
        if number not in spec:
            continue
        key, kind, repeated, oneof = spec[number]
        scalar = kind in ('u','int','sint','bool')
        if repeated and scalar and wire == 2:
            pos = 0
            while pos < len(raw):
                value, pos = take(raw, pos)
                out[key].append(value)
            continue
        if wire != (0 if scalar else 2):
            raise ValueError('wrong wire type')
        value = ((raw >> 1) ^ -(raw & 1) if kind == 'sint' else
                 raw - (1 << 64) if kind == 'int' and raw >= 1 << 63 else
                 bool(raw) if kind == 'bool' else raw if scalar else
                 raw.decode('utf-8') if kind == 'str' else
                 base64.b64encode(raw).decode() if kind == 'bytes' else decode(kind, raw))
        if oneof and any(n in out for n,_,_,o in spec.values() if o):
            raise ValueError('multiple oneof fields')
        if repeated:
            out[key].append(value)
        else:
            out[key] = value
    return out
