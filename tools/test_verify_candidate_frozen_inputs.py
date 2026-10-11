#!/usr/bin/env python3
"""Offline control tests; never invokes the verifier's Sui business commands."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_only(candidate, root):
    spec = importlib.util.spec_from_file_location('candidate_guard', candidate)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    def forbidden_command(*args, **kwargs):
        raise AssertionError('Sui business command is forbidden in frozen-input controls')

    module.command = forbidden_command
    try:
        module.verify_frozen_inputs((root / 'packages/soulidity_content').resolve(), root)
    except Exception as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        return 2
    print('Frozen input preflight PASS; no Sui business command executed')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, default=Path(__file__).with_name('verify_candidate.py'))
    parser.add_argument('--actual-root', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--validate-only', type=Path)
    args = parser.parse_args()
    if args.validate_only:
        return validate_only(args.candidate, args.validate_only)
    if not args.actual_root or not args.report:
        parser.error('--actual-root and --report are required for controls')
    actual = args.actual_root.resolve()
    snapshot = json.loads((actual / 'evidence/vendor-snapshot.json').read_text())
    manifest = (actual / 'packages/soulidity_content/Move.toml').read_text()
    before_inventory = {str(p.relative_to(actual / 'offline-vendor')): digest(p) for p in (actual / 'offline-vendor').rglob('*') if p.is_file()}
    rows = []
    cases = []

    def add(name, mutate, error='', positive=False):
        cases.append((name, mutate, error, positive))

    def manifest_change(root, old, new):
        path = root / 'move/soulidity_content/Move.toml'
        text = path.read_text()
        if old not in text:
            raise AssertionError('Control mutation input missing: ' + old)
        path.write_text(text.replace(old, new))

    def change_snapshot(root, change):
        path = root / 'evidence/vendor-snapshot.json'
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data, indent=2) + '\n')

    add('correct_frozen_git_and_vendor_copy', lambda root: None, positive=True)
    for dep, url, subdir, revision in [
        ('Sui', 'https://github.com/MystenLabs/sui.git', 'crates/sui-framework/packages/sui-framework', '2a0becb2fcc6989e492981104af67f62f2c9511a'),
        ('Walrus', 'https://github.com/MystenLabs/walrus.git', 'mainnet-contracts/walrus', 'a19764ff77f501a79db88dc6d922a2c73848e989'),
    ]:
        for key, old, new in [('git', url, 'https://example.invalid/different.git'), ('subdir', subdir, 'different/package'), ('rev', revision, '0' * 40)]:
            add(dep.lower() + '_wrong_' + key, lambda root, old=old, new=new: manifest_change(root, old, new), 'dependency ' + key + ' differs from frozen graph: ' + dep)

    def local_inputs(root):
        for name, vendor in [('Sui', 'sui-framework'), ('Walrus', 'walrus')]:
            path = root / 'move/soulidity_content/Move.toml'
            lines = path.read_text().splitlines()
            lines = [name + ' = { local = "../../offline-vendor/' + vendor + '" }' if line.startswith(name + ' = ') else line for line in lines]
            path.write_text('\n'.join(lines) + '\n')

    add('correct_local_external_dependencies_and_own_alias', local_inputs, positive=True)

    def local_mismatch(root):
        local_inputs(root)
        shutil.copytree(root / 'offline-vendor/sui-framework', root / 'selected-sui')
        manifest_change(root, '../../offline-vendor/sui-framework', '../../selected-sui')
        (root / 'selected-sui/sources/accumulator.move').write_text('changed local source\n')

    add('wrong_local_external_source', local_mismatch, 'local external dependency differs from frozen source: Sui')
    add('ambiguous_git_and_local', lambda root: manifest_change(root, 'Sui = { git', 'Sui = { local = "../../offline-vendor/sui-framework", git'), 'Ambiguous selected external dependency: Sui')
    add('duplicate_git_revision_field', lambda root: manifest_change(root, 'Sui = { git', 'Sui = { rev = "2a0becb2fcc6989e492981104af67f62f2c9511a", git'), 'Invalid or duplicate dependency field: Sui')
    add('missing_git_subdir_field', lambda root: manifest_change(root, 'subdir = "crates/sui-framework/packages/sui-framework", ', ''), 'dependency subdir differs from frozen graph: Sui')

    for label, relative in [('source', 'sui-framework/sources/unlisted.move'), ('test', 'walrus/tests/unlisted.move'), ('manifest', 'wal/Unlisted.toml'), ('other_file', 'move-stdlib/unlisted.txt'), ('unknown_package', 'unknown/sources/input.move')]:
        def extra(root, relative=relative):
            path = root / 'offline-vendor' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('unlisted input\n')
        add('extra_vendor_' + label, extra, 'input set differs from snapshot')
    for label, relative in [('source', 'sui-framework/sources/accumulator.move'), ('test', 'walrus/tests/e2e_runner.move'), ('manifest', 'wal/Move.toml'), ('published_manifest', 'wal/Published.toml')]:
        add('missing_vendor_' + label, lambda root, relative=relative: (root / 'offline-vendor' / relative).unlink(), 'input set differs from snapshot')
        add('changed_vendor_' + label, lambda root, relative=relative: (root / 'offline-vendor' / relative).write_text('changed input\n'), 'Offline vendor input changed: ' + relative)

    add('duplicate_snapshot_path', lambda root: change_snapshot(root, lambda data: data[0]['files'].append(copy.deepcopy(data[0]['files'][0]))), 'Duplicate offline vendor snapshot path')
    for label, invalid in [('absolute', '/tmp/escape.move'), ('parent_escape', 'sui-framework/../../escape.move'), ('dot_component', 'sui-framework/./Move.toml'), ('empty_component', 'sui-framework//Move.toml'), ('wrong_package_prefix', 'wal/Move.toml'), ('backslash', 'sui-framework\\Move.toml'), ('control_character', 'sui-framework/\x00Move.toml')]:
        def bad_path(root, invalid=invalid):
            change_snapshot(root, lambda data: data[0]['files'][0].update(path=invalid))
        add('invalid_snapshot_path_' + label, bad_path, 'Invalid offline vendor snapshot path')
    add('invalid_snapshot_sha256', lambda root: change_snapshot(root, lambda data: data[0]['files'][0].update(sha256='not-a-sha')), 'Invalid offline vendor snapshot SHA256')
    add('duplicate_snapshot_package', lambda root: change_snapshot(root, lambda data: data.append(copy.deepcopy(data[0]))), 'Invalid or duplicate offline vendor package')
    add('missing_snapshot_package', lambda root: change_snapshot(root, lambda data: data.pop()), 'snapshot package set differs from frozen graph')

    def file_symlink(root):
        target = root / 'offline-vendor/sui-framework/sources/accumulator.move'
        outside = root / 'outside.move'
        shutil.copy2(target, outside)
        target.unlink()
        target.symlink_to(outside)

    def directory_symlink(root):
        (root / 'offline-vendor/escape').symlink_to(root / 'move', target_is_directory=True)

    def fifo(root):
        os.mkfifo(root / 'offline-vendor/not-regular')

    add('vendor_file_symlink_same_bytes_outside', file_symlink, 'Offline vendor symlink')
    add('vendor_directory_symlink_outside', directory_symlink, 'Offline vendor symlink')
    add('vendor_non_regular_fifo', fifo, 'not a regular file or directory')

    def run(name, root, positive, expected):
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--candidate', str(args.candidate.resolve()), '--validate-only', str(root)], capture_output=True, text=True)
        okay = (result.returncode == 0 if positive else result.returncode != 0 and expected in result.stderr)
        rows.append({'case': name, 'expected_exit': '0' if positive else 'nonzero', 'actual_exit_code': result.returncode, 'passed': okay, 'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()})

    run('actual_frozen_inputs_read_only', actual, True, '')
    with tempfile.TemporaryDirectory(prefix='content-frozen-input-controls-') as directory:
        controls = Path(directory)
        for index, (name, mutate, expected, positive) in enumerate(cases):
            root = controls / ('case-' + str(index))
            (root / 'evidence').mkdir(parents=True)
            (root / 'move/soulidity_content').mkdir(parents=True)
            (root / 'packages').mkdir()
            (root / 'packages/soulidity_content').symlink_to('../move/soulidity_content', target_is_directory=True)
            (root / 'move/soulidity_content/Move.toml').write_text(manifest)
            (root / 'evidence/vendor-snapshot.json').write_text(json.dumps(snapshot, indent=2) + '\n')
            shutil.copytree(actual / 'offline-vendor', root / 'offline-vendor')
            mutate(root)
            run(name, root, positive, expected)
    after_inventory = {str(p.relative_to(actual / 'offline-vendor')): digest(p) for p in (actual / 'offline-vendor').rglob('*') if p.is_file()}
    report = {'candidate_tool': str(args.candidate.resolve()), 'candidate_tool_sha256': digest(args.candidate), 'actual_root': str(actual), 'scope': 'extracted frozen external locator and offline vendor input preflight only', 'tests': rows, 'test_count': len(rows), 'passed_count': sum(row['passed'] for row in rows), 'positive_count': sum(row['expected_exit'] == '0' for row in rows), 'negative_count': sum(row['expected_exit'] == 'nonzero' for row in rows), 'actual_vendor_inventory_count': len(after_inventory), 'actual_vendor_inputs_unchanged': before_inventory == after_inventory, 'sui_business_commands_executed': 0, 'business_19_vm_rerun': False, 'RPC': False, 'signatures': 0, 'verified': all(row['passed'] for row in rows) and before_inventory == after_inventory}
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['test_count', 'passed_count', 'positive_count', 'negative_count', 'actual_vendor_inputs_unchanged', 'sui_business_commands_executed', 'business_19_vm_rerun', 'verified']}))
    return 0 if report['verified'] else 1


if __name__ == '__main__':
    sys.exit(main())
