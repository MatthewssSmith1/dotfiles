#!/usr/bin/env python3
"""Standalone keyd backend. No implicit elevation; see README.md for API."""
import argparse
from contextlib import ExitStack
import difflib
import fcntl
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent
ORIGINAL = SOURCE.parent / "snapshots/keyd"
NAMES = ("default.conf", "toucan.conf", "air60.conf", "home-row-mods", "shared-layers")
DEVICES = {"toucan": ("usb", "bluetooth"), "air60": ("usb", "bluetooth", "receiver")}


class Blocked(RuntimeError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tree(path):
    if path.is_symlink() or not path.is_dir():
        raise Blocked(f"Not a regular directory: {path}")
    result = {}
    for p in sorted(path.iterdir()):
        if p.is_symlink() or not p.is_file():
            raise Blocked(f"Unsafe entry: {p}")
        result[p.name] = p.read_bytes()
    return result


def desired(migrate=(), source=SOURCE, original=ORIGINAL):
    if set(migrate) - DEVICES.keys():
        raise Blocked("Unknown migration target")
    for line in (original / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split()
        if name not in NAMES or digest((original / name).read_bytes()) != expected:
            raise Blocked(f"Original evidence hash mismatch: {name}")
    result = {n: (source / n).read_bytes() for n in NAMES}
    # Preserve device behavior independently of changes to generic includes.
    result["legacy-shared-layers"] = (original / "shared-layers").read_bytes()
    result["legacy-home-row-mods"] = (original / "home-row-mods").read_bytes()
    for device in DEVICES:
        name = device + ".conf"
        known = set(re.findall(rb"^k:[0-9a-f:]+$", (original / name).read_bytes(), re.M))
        intended = set(re.findall(rb"^k:[0-9a-f:]+$", result[name], re.M))
        if not known <= intended:
            raise Blocked(f"{device}: intended profile dropped a known selector")
        if device not in migrate:
            result[device + ".conf"] = (original / (device + ".conf")).read_bytes().replace(
                b"include shared-layers", b"include legacy-shared-layers"
            ).replace(b"include home-row-mods", b"include legacy-home-row-mods")
    return result


def migration_check(files, migrate, evidence, acknowledged):
    if not migrate:
        return
    if set(migrate) != set(acknowledged):
        raise Blocked("Each migration requires --ack-migration DEVICE")
    if not isinstance(evidence, dict):
        raise Blocked("Migration evidence must be a JSON object")
    for device in migrate:
        record = evidence.get(device, {})
        if not isinstance(record, dict):
            raise Blocked(f"{device}: invalid evidence record")
        if record.get("profile_sha256") != digest(files[device + ".conf"]):
            raise Blocked(f"{device}: evidence does not match intended profile")
        if not re.fullmatch(r"[0-9a-f]{64}", str(record.get("firmware_sha256", ""))):
            raise Blocked(f"{device}: persisted keymap readback hash required")
        for field in ("readback_at", "readback_record"):
            if not isinstance(record.get(field), str) or not record[field].strip():
                raise Blocked(f"{device}: dated persisted keymap readback record required ({field})")
        ids = set(re.findall(r"^k:[0-9a-f:]+$", files[device + ".conf"].decode(), re.M))
        covered = set()
        used = set()
        if not isinstance(record.get("transports"), dict):
            raise Blocked(f"{device}: transport evidence object required")
        for transport in DEVICES[device]:
            entry = record.get("transports", {}).get(transport, {})
            if not isinstance(entry, dict):
                raise Blocked(f"{device}/{transport}: invalid evidence record")
            if entry.get("status") == "not-used":
                if (not isinstance(entry.get("reason"), str) or not entry["reason"].strip()
                        or entry.get("disconnected") is not True):
                    raise Blocked(f"{device}/{transport}: not-used requires a reason and disconnected: true")
                reserved = entry.get("keyd_ids", [])
                if not isinstance(reserved, list) or any(not isinstance(i, str) or i not in ids for i in reserved):
                    raise Blocked(f"{device}/{transport}: not-used keyd_ids must list preserved profile selectors")
                covered.update(reserved)
                continue
            if "keyd_id" in entry and "keyd_ids" in entry:
                raise Blocked(f"{device}/{transport}: use keyd_id or keyd_ids, not both")
            verified = entry.get("keyd_ids", [entry.get("keyd_id")])
            if (entry.get("status") != "verified" or not isinstance(verified, list) or not verified
                    or any(not isinstance(i, str) or i not in ids
                           or not re.fullmatch(r"k:[0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{8}", i) for i in verified)
                    or len(set(verified)) != len(verified)):
                raise Blocked(f"{device}/{transport}: verified keyd ID or explicit not-used reason required")
            if not isinstance(entry.get("identity_record"), str) or not entry["identity_record"].strip():
                raise Blocked(f"{device}/{transport}: identity evidence required")
            covered.update(verified)
            used.update(verified)
        if not used:
            raise Blocked(f"{device}: test pass-through requires at least one identity-verified used transport")
        if covered != ids:
            raise Blocked(f"{device}: every profile ID must be verified or explicitly reserved on a disconnected transport")


def run(command):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Blocked(str(exc)) from exc


def validate(files, runner=run, keyd="/usr/bin/keyd"):
    help_result = runner([keyd, "--help"])
    if help_result.returncode or not re.search(r"^\s+check\s", help_result.stdout + help_result.stderr, re.M):
        raise Blocked("Installed keyd does not advertise check; no supported offline validator")

    def expand(name, stack=()):
        if name in stack or name not in files:
            raise Blocked(f"Missing/cyclic include: {name}")
        lines = []
        for line in files[name].decode().splitlines():
            if line.strip().startswith("include "):
                child = line.strip()[8:].strip()
                if child not in files:
                    raise Blocked(f"Unmanaged include: {child}")
                lines.append(expand(child, (*stack, name)))
            else:
                lines.append(line)
        return "\n".join(lines) + "\n"

    # Flatten includes so validation cannot accidentally read live /etc includes.
    with tempfile.TemporaryDirectory(prefix="keyboard-keyd-check-") as tmp:
        paths = []
        for name in sorted(files):
            if name.endswith(".conf"):
                path = Path(tmp) / name
                path.write_text(expand(name))
                paths.append(str(path))
        result = runner([keyd, "check", *paths])
        output = result.stdout + result.stderr
        if result.returncode or re.search(r"\b(error|warning|invalid|failed)\b", output, re.I):
            raise Blocked("keyd validation failed: " + output.strip())


def diff(current, wanted):
    return "".join("".join(difflib.unified_diff(
        current.get(n, b"").decode().splitlines(True), wanted[n].decode().splitlines(True),
        fromfile="live/" + n, tofile="intended/" + n)) for n in sorted(wanted))


def conflicts(current, wanted, original=ORIGINAL, source=SOURCE):
    unknown = [n for n in current if n.endswith(".conf") and n not in wanted]
    if unknown:
        raise Blocked("Unmanaged profiles may overlap: " + ", ".join(unknown))
    versions = [desired(combo, source, original) for size in range(3)
                for combo in itertools.combinations(DEVICES, size)]
    for n in wanted:
        allowed = {v[n] for v in versions}
        if (original / n).is_file():
            allowed.add((original / n).read_bytes())
        if n in current and current[n] not in allowed:
            raise Blocked(f"Unexpected managed-file content: {n}")
    for device in DEVICES:
        n = device + ".conf"
        if current.get(n) == (source / n).read_bytes() and wanted[n] != current[n]:
            raise Blocked(f"Refusing implicit migration reversal: {device}")
    # Unrelated includes could depend on files being changed. Refuse rather than guess.
    for n in current.keys() - wanted.keys():
        if b"include " in current[n]:
            raise Blocked(f"Unmanaged include consumer: {n}")


def snapshot(target, state):
    if state.resolve().is_relative_to(SOURCE.parent.parent):
        raise Blocked("Runtime backups must be outside the repository")
    before = tree(target)
    if set(before) & {"manifest.json", "intended.diff", "recovery.json"}:
        raise Blocked("Live directory contains reserved backup record names")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if state.is_symlink() or state.stat().st_uid != os.geteuid() or stat.S_IMODE(state.stat().st_mode) != 0o700:
        raise Blocked("Backup state must be owned by caller, non-symlink, mode 0700")
    backup = Path(tempfile.mkdtemp(prefix="keyd-", dir=state))
    metadata = {}
    for n, data in before.items():
        p = backup / n
        p.write_bytes(data)
        p.chmod(0o600)
        s = (target / n).stat()
        metadata[n] = {"sha256": digest(data), "mode": stat.S_IMODE(s.st_mode), "uid": s.st_uid, "gid": s.st_gid}
    (backup / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (backup / "manifest.json").chmod(0o600)
    for p in backup.iterdir():
        with p.open("rb") as saved:
            os.fsync(saved.fileno())
    for directory in (backup, state):
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    if tree(target) != before:
        raise Blocked(f"Source changed during backup; retained {backup}")
    return backup, before, metadata


def replace(path, data, mode=0o644, uid=0, gid=0):
    fd, tmp = tempfile.mkstemp(prefix=".keyboard-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
            os.fchmod(f.fileno(), mode)
            os.fchown(f.fileno(), uid, gid)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def apply(target, state, wanted, *, execute=False, layout_ack=False, runner=run,
          writer=replace, privileged=None, source=SOURCE, original=ORIGINAL,
          migrate=(), evidence=None, acknowledged=()):
    if not execute or not layout_ack:
        raise Blocked("Apply requires --execute and --ack-layout-review")
    if privileged is None:
        privileged = os.geteuid() == 0
        for path in (target, *target.iterdir()):
            s = path.lstat()
            if s.st_uid != 0 or s.st_gid != 0 or s.st_mode & 0o022:
                raise Blocked(f"Privileged apply requires root-owned, non-writable live paths: {path}")
    if not privileged:
        raise Blocked("No automatic elevation. Review README; explicitly authorize privileged apply")
    if wanted != desired(migrate, source, original):
        raise Blocked("Install payload differs from selected repository configuration")
    migration_check(wanted, migrate, evidence or {}, acknowledged)
    if target.is_symlink():
        raise Blocked("Symlink target refused")
    with ExitStack() as cleanup:
        lock = os.open(target, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        cleanup.callback(os.close, lock)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise Blocked("Another keyd apply is running") from exc
        current = tree(target)
        conflicts(current, wanted, original, source)
        validate(wanted, runner)
        changed = [n for n in wanted if current.get(n) != wanted[n]]
        if not changed:
            return {"result": "unchanged", "runtime_verified": False}
        active = runner(["/usr/bin/systemctl", "is-active", "keyd.service"])
        if active.returncode or active.stdout.strip() != "active":
            raise Blocked("keyd service must be active before apply")
        backup, before, metadata = snapshot(target, state)
        (backup / "intended.diff").write_text(diff(before, wanted))
        (backup / "intended.diff").chmod(0o600)
        validate(before, runner)
        if tree(target) != current:
            raise Blocked(f"Concurrent change before install; backup: {backup}")
        installed = []
        try:
            for n in changed:
                # Track before calling writer, including replace-then-error failures.
                installed.append(n)
                writer(target / n, wanted[n])
            if any((target / n).read_bytes() != wanted[n] for n in wanted):
                raise Blocked("Installed readback mismatch")
            result = runner(["/usr/bin/keyd", "reload"])
            if result.returncode:
                raise Blocked("Reload failed: " + result.stdout + result.stderr)
            active = runner(["/usr/bin/systemctl", "is-active", "keyd.service"])
            if active.returncode or active.stdout.strip() != "active":
                raise Blocked("keyd service not active after reload")
        except Exception as exc:
            recovery_errors = []
            for n in reversed(installed):
                try:
                    now = tree(target).get(n)
                    if now == before.get(n):
                        continue
                    if now != wanted[n]:
                        raise Blocked(f"Concurrent edit to {n}; refusing overwrite")
                    if n in before:
                        m = metadata[n]
                        writer(target / n, before[n], m["mode"], m["uid"], m["gid"])
                    else:
                        (target / n).unlink()
                except Exception as restore_error:
                    recovery_errors.append(str(restore_error))
            files_restored = not recovery_errors
            if files_restored:
                try:
                    result = runner(["/usr/bin/keyd", "reload"])
                    if result.returncode:
                        recovery_errors.append("Recovery reload failed")
                    active = runner(["/usr/bin/systemctl", "is-active", "keyd.service"])
                    if active.returncode or active.stdout.strip() != "active":
                        recovery_errors.append("keyd service not active after recovery reload")
                except Exception as reload_error:
                    recovery_errors.append(str(reload_error))
            report = {"failure": str(exc), "recovery_errors": recovery_errors,
                      "files_restored": files_restored}
            (backup / "recovery.json").write_text(json.dumps(report, indent=2) + "\n")
            (backup / "recovery.json").chmod(0o600)
            raise Blocked(f"Apply failed; backup/recovery record: {backup}; {report}") from exc
        return {"result": "installed", "backup": str(backup), "runtime_verified": False,
                "note": "Files match and reload accepted; physical output testing still required"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "status", "diff", "snapshot", "apply", "verify"), nargs="?", default="status")
    parser.add_argument("--target", type=Path, default=Path("/etc/keyd"))
    parser.add_argument("--state", type=Path, default=Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "keyboards/keyd")
    parser.add_argument("--migrate", action="append", choices=DEVICES, default=[],
                        help="select target-specific test pass-through after persisted readback and identity checks")
    parser.add_argument("--ack-migration", action="append", choices=DEVICES, default=[],
                        help="acknowledge starting test pass-through, not completed physical testing")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--ack-layout-review", action="store_true")
    args = parser.parse_args(argv)
    try:
        wanted = desired(args.migrate)
        evidence = json.loads(args.evidence.read_text()) if args.evidence else {}
        if args.command in ("check", "apply", "verify"):
            migration_check(wanted, args.migrate, evidence, args.ack_migration)
        if args.command == "apply":
            if args.target != Path("/etc/keyd") or args.state != Path("/var/lib/keyboard-keyd"):
                raise Blocked("Privileged CLI apply fixes --target /etc/keyd and requires --state /var/lib/keyboard-keyd")
            print(json.dumps(apply(args.target, args.state, wanted, execute=args.execute,
                                   layout_ack=args.ack_layout_review, migrate=args.migrate,
                                   evidence=evidence, acknowledged=args.ack_migration), indent=2))
        elif args.command == "snapshot":
            print(snapshot(args.target, args.state)[0])
        else:
            current = tree(args.target)
            if args.command == "diff":
                print(diff(current, wanted), end="")
            elif args.command == "status":
                print(json.dumps({"target": str(args.target), "files_match": all(current.get(n) == v for n, v in wanted.items()),
                                  "migration_requested": args.migrate, "runtime_verified": False,
                                  "live_sha256": {n: digest(v) for n, v in current.items()}}, indent=2))
            else:
                conflicts(current, wanted)
                validate(wanted)
                if args.command == "verify" and any(current.get(n) != v for n, v in wanted.items()):
                    raise Blocked("Installed files differ; verify is file-level only, not hardware verification")
                print("Validated intended files; physical output and transport verification remain manual")
        return 0
    except (Blocked, OSError, ValueError, TypeError) as exc:
        print(f"keyd: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
