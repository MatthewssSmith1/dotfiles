"""Offline validation and explicit, narrowly allowlisted Toucan Studio operations."""
import argparse
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import select
import stat
import subprocess
import sys
import tempfile
import termios
import time

HERE = Path(__file__).resolve().parent
ORIGINALS = HERE.parent / 'snapshots' / 'toucan'
spec = importlib.util.spec_from_file_location('toucan_protocol', HERE / 'protocol.py')
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
PORT = '/dev/serial/by-id/usb-ZMK_Project_Toucan_93F54E4E61BA5937-if00'
GETTERS = {'core': {'get_device_info', 'get_lock_state'},
           'keymap': {'get_keymap', 'get_physical_layouts', 'check_unsaved_changes'},
           'behaviors': {'list_all_behaviors', 'get_behavior_details'}}
SETTERS = {'set_layer_binding', 'set_layer_props', 'save_changes'}


class Error(RuntimeError):
    pass


def load(path):
    def pairs(items):
        result = {}
        for k,v in items:
            if k in result:
                raise Error(f'duplicate JSON key: {k}')
            result[k] = v
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=pairs)


def original():
    result = load(ORIGINALS / 'snapshot.json')
    result['behavior_details'] = load(ORIGINALS / 'metadata.json')['behavior_details']
    return result


def status(*, sysfs_root='/sys'):
    """USB presence inventory only; never open a device or query Studio."""
    root = Path(sysfs_root)
    expected = original()['usb_identity']
    devices = []
    for device in (root / 'bus/usb/devices').iterdir():
        try:
            identity = {key: (device / attr).read_text().strip() for key,attr in (
                ('ID_VENDOR_ID','idVendor'), ('ID_MODEL_ID','idProduct'),
                ('ID_SERIAL_SHORT','serial'))}
        except FileNotFoundError:
            continue  # USB interface, unrelated device, or unplug during enumeration.
        if any(value != expected[key] for key,value in identity.items()):
            continue
        ports = []
        for tty in (root / 'class/tty').iterdir():
            try:
                if (tty / 'device').resolve(strict=True).is_relative_to(device.resolve(strict=True)):
                    ports.append('/dev/' + tty.name)
            except FileNotFoundError:
                continue
        devices.append({'sysfs_path': str(device), 'usb_identity': identity, 'ports': sorted(ports)})
    return {'present': bool(devices), 'devices': sorted(devices, key=lambda d:d['sysfs_path']),
            'source': 'sysfs', 'studio_state': 'not queried'}


class SerialRPC:
    """Linux CDC transport, no pyserial/protobuf dependencies or automatic discovery."""
    def __init__(self, port=PORT, *, writable=False, timeout=10):
        self.port, self.writable, self.timeout = str(port), writable, timeout
        self.fd = None
        self.sequence = 0

    def __enter__(self):
        if self.fd is not None:
            raise Error('transport already open')
        self.attrs = None
        self.exclusive = False
        expected = original()['usb_identity']
        props = subprocess.run(['udevadm','info','--query=property','--name='+self.port],
                               check=True, capture_output=True, text=True, timeout=5).stdout
        actual = dict(line.split('=',1) for line in props.splitlines() if '=' in line)
        if any(actual.get(k) != expected[k] for k in expected):
            raise Error('USB identity differs from captured Toucan; refusing connection')
        self.fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK | os.O_CLOEXEC)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.ioctl(self.fd, termios.TIOCEXCL)
            self.exclusive = True
            device = os.fstat(self.fd)
            if not stat.S_ISCHR(device.st_mode):
                raise Error('not a character device')
            # TIOCEXCL prevents new nonprivileged opens, but not pre-existing handles.
            # Audit same-effective-UID processes only, not system-wide exclusivity.
            incomplete = False
            for process in Path('/proc').iterdir():
                if not process.name.isdigit():
                    continue
                try:
                    uid_lines = [line.split() for line in (process / 'status').read_text().splitlines()
                                 if line.startswith('Uid:')]
                    if len(uid_lines) != 1 or len(uid_lines[0]) != 5:
                        raise Error(f'cannot determine effective UID for PID {process.name}')
                    if int(uid_lines[0][2]) != os.geteuid():
                        continue
                    for fd in (process / 'fd').iterdir():
                        if int(process.name) == os.getpid() and fd.name == str(self.fd):
                            continue
                        try:
                            other = fd.stat()
                        except FileNotFoundError:
                            continue
                        except PermissionError:
                            incomplete = True
                            continue
                        if stat.S_ISCHR(other.st_mode) and other.st_rdev == device.st_rdev:
                            raise Error(f'Toucan already open by PID {process.name}')
                except FileNotFoundError:
                    continue
                except PermissionError:
                    incomplete = True
            if incomplete:
                print('toucan: warning: same-effective-UID access audit incomplete: '
                      'inaccessible process status or FDs; continuing with flock/TIOCEXCL '
                      'and visible-FD checks, not system-wide exclusivity. '
                      'Close browser/Studio/VIA clients; do not use sudo or stop unrelated services.',
                      file=sys.stderr)
            self.attrs = termios.tcgetattr(self.fd)
            attrs = copy.deepcopy(self.attrs)
            attrs[0] = attrs[1] = attrs[3] = 0
            attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
            attrs[4] = attrs[5] = termios.B115200
            attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
            termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self.fd is not None:
            try:
                try:
                    if self.attrs is not None:
                        termios.tcsetattr(self.fd, termios.TCSANOW, self.attrs)
                finally:
                    if getattr(self, 'exclusive', False):
                        fcntl.ioctl(self.fd, termios.TIOCNXCL)
            finally:
                os.close(self.fd)
                self.fd = None
                self.exclusive = False

    def call(self, subsystem, method, value=True):
        if method not in GETTERS.get(subsystem, set()) and not (
                self.writable and subsystem == 'keymap' and method in SETTERS):
            raise Error(f'RPC not allowed: {subsystem}.{method}')
        self.sequence += 1
        payload = protocol.encode('Request', {'request_id': self.sequence,
                                             subsystem: {method: value}})
        frame = b'\xab' + b''.join((b'\xac' if b in (171,172,173) else b'') + bytes([b])
                                  for b in payload) + b'\xad'
        deadline = time.monotonic() + self.timeout
        while frame:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([], [self.fd], [], remaining)[1]:
                raise TimeoutError(f'send timeout: {method}')
            count = os.write(self.fd, frame)
            if count == 0:
                raise Error('serial disconnected during send')
            frame = frame[count:]
        frame, escaped = None, False
        while time.monotonic() < deadline:
            if not select.select([self.fd], [], [], max(0, deadline-time.monotonic()))[0]:
                break
            chunk = os.read(self.fd, 1)
            if not chunk:
                raise Error('serial disconnected')
            b = chunk[0]
            if frame is None:
                if b == 171:
                    frame = bytearray()
                continue
            if escaped:
                frame.append(b)
                escaped = False
            elif b == 172:
                escaped = True
            elif b == 171:
                frame.clear()
            elif b == 173:
                response = protocol.decode('Response', bytes(frame))
                frame = None
                if 'notification' in response:
                    if response['notification'].get('core', {}).get('lock_state_changed') == 0:
                        raise Error('Studio locked during operation')
                    continue
                rr = response.get('request_response', {})
                if rr.get('request_id') != self.sequence:
                    raise Error('unexpected request ID: competing client or stale response')
                if method not in rr.get(subsystem, {}):
                    raise Error(f'RPC error/unexpected response: {rr}')
                return rr[subsystem][method]
            else:
                frame.append(b)
            if frame is not None and len(frame) > 1024*1024:
                raise Error('oversized RPC frame')
        raise TimeoutError(f'receive timeout: {subsystem}.{method}')


def unlocked(rpc):
    if rpc.call('core','get_lock_state') != 1:
        raise Error('Studio locked; use physical Nav+Z, no software unlock attempted')


def snapshot(rpc):
    """Return JSON-compatible getter-only snapshot. Unknown behavior 0 is not queried."""
    info = rpc.call('core','get_device_info')
    if info != original()['device_info']:
        raise Error('RPC device identity mismatch')
    unlocked(rpc)
    before = rpc.call('keymap','check_unsaved_changes')
    keymap = rpc.call('keymap','get_keymap')
    layouts = rpc.call('keymap','get_physical_layouts')
    available = rpc.call('behaviors','list_all_behaviors')
    details = {str(i): rpc.call('behaviors','get_behavior_details', {'behavior_id': i})
               for i in available['behaviors']}
    after = rpc.call('keymap','check_unsaved_changes')
    unlocked(rpc)
    if rpc.call('keymap','get_keymap') != keymap:
        raise Error('keymap changed during snapshot')
    return {'device_info': info, 'keymap': keymap, 'physical_layouts': layouts,
            'available_behaviors': available, 'behavior_details': details,
            'unsaved_before': before, 'unsaved_after': after}


def validate(desired, current=None):
    """Validate native keymap; legacy anomalies may be retained, never restored."""
    baseline = original()
    current = baseline if current is None else current
    if current['device_info'] != baseline['device_info']:
        raise Error('wrong target identity')
    if current['physical_layouts'] != baseline['physical_layouts']:
        raise Error('physical layout/geometry changed')
    if not isinstance(desired, dict) or set(desired) != {'layers','available_layers','max_layer_name_length'}:
        raise Error('expected native get_keymap response shape')
    layers = desired['layers']
    if (not isinstance(layers, list) or not all(isinstance(l,dict) for l in layers)
            or [l.get('id') for l in layers] != [0,2,1,3]):
        raise Error('stable layer IDs/order must remain 0,2,1,3')
    if [l['id'] for l in current['keymap']['layers']] != [0,2,1,3]:
        raise Error('live layer IDs/order differ')
    for key in ('available_layers','max_layer_name_length'):
        if type(desired[key]) is not int or desired[key] != current['keymap'][key]:
            raise Error(f'capability changed: {key}')
    advertised = current['available_behaviors']['behaviors']
    for layer, live, old in zip(layers, current['keymap']['layers'], baseline['keymap']['layers']):
        if set(layer) != {'id','name','bindings'} or type(layer['id']) is not int:
            raise Error('invalid layer schema')
        name = layer['name']
        if not isinstance(name,str) or not name or '\0' in name or len(name.encode()) > desired['max_layer_name_length']:
            raise Error('invalid layer name')
        if not isinstance(layer['bindings'],list) or len(layer['bindings']) != 42 or len(live['bindings']) != 42:
            raise Error('expected 42 key positions')
        for pos,binding in enumerate(layer['bindings']):
            if not isinstance(binding,dict) or set(binding) != {'behavior_id','param1','param2'}:
                raise Error('invalid binding schema')
            if any(type(v) is not int or not 0 <= v <= 0xffffffff for v in binding.values()):
                raise Error('binding values must be uint32 integers')
            anomaly_position = layer['id'] == 3 and pos in (0,41)
            if anomaly_position:
                # Permit read-only verification of an uncorrected snapshot.
                if binding == old['bindings'][pos] == live['bindings'][pos]:
                    continue
                if binding != {'behavior_id':4,'param1':0,'param2':0}:
                    raise Error(f'legacy anomaly 3:{pos}: only None correction allowed; restoration unsupported')
                # Corrections still require the standard firmware metadata checks.
            protected = (pos >= 36 or (layer['id'] == 1 and pos in (17,25,28,29))
                         or (layer['id'] == 0 and 24 <= pos < 36))
            if protected and not anomaly_position and binding != old['bindings'][pos]:
                raise Error(f'protected thumb, Base bottom row, mouse, or unlock binding: {layer["id"]}:{pos}')
            bid = binding['behavior_id']
            metadata = current['behavior_details'].get(str(bid))
            if bid not in advertised or metadata != baseline['behavior_details'].get(str(bid)):
                raise Error(f'firmware-local behavior identity/schema mismatch: {bid}')
            # The backend intentionally supports only reviewed behavior families.
            if bid not in (1,4,8,12,13,14,15,22,23,24):
                raise Error(f'unreviewed behavior {bid}')
            if bid == 22 and binding['param1'] not in (1,2,3):
                raise Error('bond clear/disconnect binding forbidden')
            sets = metadata['metadata'] or [{'param1': [], 'param2': []}]
            def accepts(value, choices):
                if not choices:
                    return value == 0
                for choice in choices:
                    if 'constant' in choice and value == choice['constant']:
                        return True
                    if 'nil' in choice and value == 0:
                        return True
                    if 'range' in choice and choice['range']['min'] <= value <= choice['range']['max']:
                        return True
                    if 'layer_id' in choice and value in (0,1,2,3):
                        return True
                    if 'hid_usage' in choice:
                        page, usage = (value >> 16) & 255, value & 65535
                        maximum = choice['hid_usage'].get({7:'keyboard_max',12:'consumer_max'}.get(page,''), -1)
                        if 0 < usage <= maximum:
                            return True
                return False
            if not any(all(accepts(binding[p], s[p]) for p in ('param1','param2')) for s in sets):
                raise Error(f'invalid parameters at {layer["id"]}:{pos}: {binding}')
    return desired


def diff(current, desired):
    """Pure validated diff; returns setter-shaped changes with old values."""
    validate(desired, current)
    changes = []
    for live,want in zip(current['keymap']['layers'], desired['layers']):
        if live['name'] != want['name']:
            changes.append({'method':'set_layer_props', 'request':{'layer_id':want['id'],'name':want['name']},
                            'before':live['name']})
        for pos,(a,b) in enumerate(zip(live['bindings'],want['bindings'])):
            if a != b:
                changes.append({'method':'set_layer_binding', 'request':{'layer_id':want['id'],
                                'key_position':pos,'binding':b}, 'before':a})
    return changes


def verify(rpc, desired):
    current = snapshot(rpc)
    changes = diff(current, desired)
    if current['unsaved_before'] or current['unsaved_after'] or changes:
        raise Error(f'verification failed: pending changes or {len(changes)} mismatches')
    return {'verified': True, 'changes': []}


def write_record(path, value):
    with open(path, 'x', encoding='utf-8', opener=lambda p,f: os.open(p,f,0o600)) as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


def apply(rpc, desired, *, backup_root=None):
    """Explicit mutation API. Raises Error with recovery directory on partial failure."""
    validate(desired)
    current = snapshot(rpc)
    if current['unsaved_before'] or current['unsaved_after']:
        raise Error('pending unsaved changes: refusing to save or discard another session')
    changes = diff(current, desired)
    if not changes:
        return {'changed': False, 'changes': [], 'backup': None}
    root = Path(backup_root) if backup_root else Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state')) / 'keyboards/toucan'
    if root.resolve().is_relative_to(HERE.parent.parent):
        raise Error('routine backups must be outside the repository')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
        raise Error('backup root must be owned by current user, mode 0700, not a symlink')
    backup = Path(tempfile.mkdtemp(prefix='apply-', dir=root))
    write_record(backup/'before.json', current)
    write_record(backup/'desired.json', desired)
    write_record(backup/'diff.json', changes)
    directory = os.open(backup, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    attempted, completed = [], []
    try:
        # Recheck after disk I/O, immediately before the first setter.
        unlocked(rpc)
        if rpc.call('keymap','check_unsaved_changes') or rpc.call('keymap','get_keymap') != current['keymap']:
            raise Error('device changed after preflight')
        for change in changes:
            attempted.append(change)
            if rpc.call('keymap', change['method'], change['request']) != 0:
                raise Error(f'setter rejected: {change}')
            completed.append(change)
        if rpc.call('keymap','get_keymap') != desired:
            raise Error('RAM readback mismatch; not saving')
        if rpc.call('keymap','save_changes') != {'ok': True}:
            raise Error('save failed; persistence may be partial')
        verify(rpc, desired)
        write_record(backup/'result.json', {'ok':True,'completed':completed})
    except BaseException as exc:
        try:
            write_record(backup/'failure.json', {'error':str(exc),'attempted':attempted,
                                                'completed':completed,'automatic_rollback':False})
        finally:
            raise Error(f'apply failed; no automatic save/discard/rollback; recovery: {backup}: {exc}') from exc
    return {'changed':True, 'changes':changes, 'backup':str(backup)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('status','check','snapshot','diff','apply','verify'))
    parser.add_argument('--keymap', default=str(HERE/'keymap.json'))
    parser.add_argument('--port', default=PORT)
    parser.add_argument('--from-snapshot', help='offline diff input; no serial connection')
    parser.add_argument('--backup-root')
    parser.add_argument('--ack-layout-review', action='store_true',
                        help='acknowledge review of intended layout before explicit apply')
    args = parser.parse_args(argv)
    try:
        if args.command == 'apply' and not args.ack_layout_review:
            raise Error('apply requires --ack-layout-review; no connection opened')
        if args.from_snapshot and args.command != 'diff':
            raise Error('--from-snapshot is only valid with diff')
        desired = load(args.keymap) if args.command not in ('status','snapshot') else None
        if args.command == 'status':
            result = status()
        elif args.command == 'check':
            validate(desired)
            result = {'valid':True}
        elif args.from_snapshot:
            result = diff(load(args.from_snapshot), desired)
        else:
            with SerialRPC(args.port, writable=args.command == 'apply') as rpc:
                result = (snapshot(rpc) if args.command == 'snapshot' else
                          diff(snapshot(rpc), desired) if args.command == 'diff' else
                          verify(rpc, desired) if args.command == 'verify' else
                          apply(rpc, desired, backup_root=args.backup_root))
        print(json.dumps(result, indent=2))
        return 0
    except (Error, ValueError, OSError, subprocess.SubprocessError) as exc:
        print(str(exc), file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
