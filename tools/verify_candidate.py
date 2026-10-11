#!/usr/bin/env python3
"""Build frozen CONTENT9 source and its 19 scoped regressions in a local-only graph.

Never overwrites historical evidence, changes a consumer, uses RPC, or signs.
Each invocation writes a fresh evidence/verifier-runs directory. Dependency
manifests are rewritten only in that graph; their exact source and diff remain.
"""
import argparse
import base64
import difflib
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

CLI_DEFAULT = '/Users/naoer/.codex/worktrees/soul-dof-v1-rebuild/soulidity/output/contract-rebuild/local-ptb-2026-10-08/tooling/sui'
CLI_SHA = '1d7baa7c7314113671415acfa20279b1eedb6ae6d04f286988a00da285e769c3'
NINE = sorted('authority authorization blob_custody document kind_registry paid_access paged_store permissions storage'.split())
EXTERNAL_DEPENDENCIES = {
    'Sui': ('https://github.com/MystenLabs/sui.git', 'crates/sui-framework/packages/sui-framework', '2a0becb2fcc6989e492981104af67f62f2c9511a', 'sui-framework'),
    'Walrus': ('https://github.com/MystenLabs/walrus.git', 'mainnet-contracts/walrus', 'a19764ff77f501a79db88dc6d922a2c73848e989', 'walrus'),
}
VENDOR_PACKAGES = frozenset(['sui-framework', 'move-stdlib', 'walrus', 'wal'])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def copy_package(source, destination, with_tests=False):
    destination.mkdir()
    shutil.copytree(source / 'sources', destination / 'sources')
    if with_tests and (source / 'tests').exists():
        shutil.copytree(source / 'tests', destination / 'tests')
    for name in ['Move.toml', 'Published.toml']:
        if (source / name).exists():
            shutil.copy2(source / name, destination / name)


def local_dependency(package, name):
    text = (package / 'Move.toml').read_text()
    m = re.search(r'^' + re.escape(name) + r'\s*=\s*\{[^\n]*local\s*=\s*"([^"]+)"', text, re.M)
    if not m:
        raise ValueError('Expected exact local dependency ' + name + ' in ' + str(package))
    return (package / m.group(1)).resolve()


def dependency_fields(manifest, name):
    """Read the existing one-line dependency format without substring matches."""
    selected = []
    section = None
    for line in manifest.splitlines():
        header = re.fullmatch(r'\s*\[([^\]]+)\]\s*(?:#.*)?', line)
        if header:
            section = header.group(1)
        elif section == 'dependencies' and re.match(r'^\s*' + re.escape(name) + r'\s*=', line):
            selected.append(line)
    if len(selected) != 1:
        raise ValueError('Expected one selected external dependency: ' + name)
    entry = re.fullmatch(r'\s*' + re.escape(name) + r'\s*=\s*\{(.*)\}\s*(?:#.*)?', selected[0])
    if not entry:
        raise ValueError('Expected inline selected external dependency: ' + name)
    fields = {}
    rest = entry.group(1).strip()
    field = re.compile(r'''([A-Za-z_][A-Za-z_0-9-]*)\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*'|true|false)''')
    while rest:
        match = field.match(rest)
        if not match or match.group(1) in fields:
            raise ValueError('Invalid or duplicate dependency field: ' + name)
        key, value = match.groups()
        if value.startswith('"'):
            value = json.loads(value)
        elif value.startswith("'"):
            value = value[1:-1]
        else:
            value = value == 'true'
        fields[key] = value
        rest = rest[match.end():].strip()
        if rest:
            if not rest.startswith(','):
                raise ValueError('Invalid dependency field separator: ' + name)
            rest = rest[1:].strip()
            if not rest:
                raise ValueError('Invalid trailing dependency field separator: ' + name)
    return fields


def verify_external_dependencies(package, root):
    manifest = (package / 'Move.toml').read_text()
    for name, (url, subdir, revision, vendor) in EXTERNAL_DEPENDENCIES.items():
        fields = dependency_fields(manifest, name)
        if 'git' in fields:
            if 'local' in fields:
                raise ValueError('Ambiguous selected external dependency: ' + name)
            for key, expected in [('git', url), ('subdir', subdir), ('rev', revision)]:
                if fields.get(key) != expected:
                    raise ValueError('Selected external dependency ' + key + ' differs from frozen graph: ' + name)
        else:
            if not isinstance(fields.get('local'), str) or any(key in fields for key in ['subdir', 'rev']):
                raise ValueError('Expected unambiguous local external dependency: ' + name)
            actual_dep = (package / fields['local']).resolve()
            actual = {str(p.relative_to(actual_dep / 'sources')): sha(p.read_bytes()) for p in (actual_dep / 'sources').rglob('*.move')}
            frozen_dep = root / 'offline-vendor' / vendor / 'sources'
            frozen = {str(p.relative_to(frozen_dep)): sha(p.read_bytes()) for p in frozen_dep.rglob('*.move')}
            if actual != frozen:
                raise ValueError('Selected local external dependency differs from frozen source: ' + name)


def verify_vendor_snapshot(vendor_root, records):
    """Require the entire offline input inventory, safe paths and exact bytes."""
    if vendor_root.is_symlink() or not vendor_root.is_dir():
        raise ValueError('Offline vendor root must be a regular directory')
    if not isinstance(records, list):
        raise ValueError('Offline vendor snapshot must be a list')
    expected = {}
    packages = set()
    for record in records:
        if not isinstance(record, dict) or record.get('name') not in VENDOR_PACKAGES or record['name'] in packages:
            raise ValueError('Invalid or duplicate offline vendor package')
        packages.add(record['name'])
        if not isinstance(record.get('files'), list) or not record['files']:
            raise ValueError('Offline vendor package must list its files: ' + record['name'])
        for item in record['files']:
            if not isinstance(item, dict):
                raise ValueError('Invalid offline vendor snapshot item')
            path, digest = item.get('path'), item.get('sha256')
            if not isinstance(path, str) or '\\' in path or any(ord(c) < 32 for c in path):
                raise ValueError('Invalid offline vendor snapshot path: ' + repr(path))
            parts = path.split('/')
            if len(parts) < 2 or parts[0] != record['name'] or any(part in ['', '.', '..'] for part in parts):
                raise ValueError('Invalid offline vendor snapshot path: ' + path)
            if path in expected:
                raise ValueError('Duplicate offline vendor snapshot path: ' + path)
            if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
                raise ValueError('Invalid offline vendor snapshot SHA256: ' + path)
            expected[path] = digest
    if packages != VENDOR_PACKAGES:
        raise ValueError('Offline vendor snapshot package set differs from frozen graph')
    actual = {}
    for path in vendor_root.rglob('*'):
        relative = str(path.relative_to(vendor_root))
        if path.is_symlink():
            raise ValueError('Offline vendor symlink is not a frozen regular input: ' + relative)
        if path.is_file():
            actual[relative] = path
        elif not path.is_dir():
            raise ValueError('Offline vendor input is not a regular file or directory: ' + relative)
    missing, extra = sorted(expected.keys() - actual.keys()), sorted(actual.keys() - expected.keys())
    if missing or extra:
        raise ValueError('Offline vendor input set differs from snapshot; missing=' + repr(missing) + '; extra=' + repr(extra))
    boundary = vendor_root.resolve()
    for relative, path in actual.items():
        try:
            path.resolve(strict=True).relative_to(boundary)
        except ValueError:
            raise ValueError('Offline vendor input escapes frozen root: ' + relative)
        if sha(path.read_bytes()) != expected[relative]:
            raise ValueError('Offline vendor input changed: ' + relative)


def verify_frozen_inputs(package, root):
    verify_vendor_snapshot(root / 'offline-vendor', json.loads((root / 'evidence/vendor-snapshot.json').read_text()))
    verify_external_dependencies(package, root)


def rewrite_dependencies(package, replacements, diffs):
    path = package / 'Move.toml'
    before = path.read_text()
    after = before
    for name, replacement in replacements.items():
        after, count = re.subn(r'^' + re.escape(name) + r'\s*=\s*\{[^\n]*\}\s*$', name + ' = ' + replacement, after, flags=re.M)
        if count != 1:
            raise ValueError('Expected one ' + name + ' dependency in ' + str(package))
    if 'git =' in after:
        raise ValueError('Remote dependency remains in offline graph: ' + str(package))
    path.write_text(after)
    diffs.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=package.name + '/original-Move.toml', tofile=package.name + '/offline-Move.toml'))


def command(cli, arguments, directory, label):
    cmd = [str(cli)] + arguments
    start = time.time()
    with (directory / (label + '.stdout.log')).open('w') as out, (directory / (label + '.stderr.log')).open('w') as err:
        result = subprocess.run(cmd, stdout=out, stderr=err)
    record = {'command': cmd, 'exit_code': result.returncode, 'elapsed_seconds': time.time() - start,
              'RPC': False, 'graph_dependencies': 'all local frozen source', 'default_test_budget_unchanged': True}
    write_json(directory / (label + '-command.json'), record)
    return result.returncode


def role(name):
    if name in NINE:
        return 'content'
    if name == 'soul':
        return 'standard'
    if name in ['economics', 'source_authority', 'package_roles', 'revenue']:
        return 'foundation'
    if name in ['blob', 'system']:
        return 'walrus'
    if name == 'wal':
        return 'wal'
    return None


def normalized_addresses(data, reader):
    _, handles = reader.module_handles(data)
    roles = {}
    for handle in handles:
        label = role(handle['module'])
        if label:
            roles.setdefault(handle['address'], set()).add(label)
    if any(len(labels) != 1 for labels in roles.values()):
        raise ValueError('Ambiguous address-role normalization')
    count, pos = reader.uleb(data, 8)
    tables = {}
    for _ in range(count):
        kind = data[pos]
        offset, pos = reader.uleb(data, pos + 1)
        size, pos = reader.uleb(data, pos)
        tables[kind] = (offset, size)
    offset, size = tables[8]
    output = bytearray(data)
    for at in range(pos + offset, pos + offset + size, 32):
        address = '0x' + data[at:at + 32].hex()
        if address in roles:
            output[at:at + 32] = hashlib.sha256(('content9-address-role:' + next(iter(roles[address]))).encode()).digest()
    return bytes(output), handles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, help='Imported CONTENT9 package; local Standard/Foundation dependencies must resolve')
    parser.add_argument('--cli', type=Path, default=Path(CLI_DEFAULT))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    package = (args.package or root / 'packages/soulidity_content').resolve()
    if sha(args.cli.read_bytes()) != CLI_SHA:
        raise ValueError('Fixed Sui CLI SHA256 mismatch')
    files = sorted((package / 'sources').rglob('*.move'), key=lambda p: p.stem)
    if [p.stem for p in files] != NINE:
        raise ValueError('Production source root must contain exactly CONTENT9')
    expected = {r['module']: r['source_sha256'] for r in json.loads((root / 'evidence/source-diff-review.json').read_text())['modules'] if r['candidate_included']}
    for path in files:
        if sha(path.read_bytes()) != expected[path.stem]:
            raise ValueError('Production source differs from fixed CONTENT9 snapshot: ' + path.name)
    for item in json.loads((root / 'evidence/test-provenance.json').read_text())['files']:
        if sha((root / item['file']).read_bytes()) != item['candidate_sha256']:
            raise ValueError('Scoped original test fixture changed: ' + item['file'])
    verify_frozen_inputs(package, root)
    standard = local_dependency(package, 'SoulidityStandard')
    foundation = local_dependency(package, 'SoulidityFoundation')
    for dep in [standard, foundation]:
        frozen_name = 'soulidity_standard' if dep == standard else 'soulidity_foundation'
        frozen_sources = root / 'packages' / frozen_name / 'sources'
        if sorted(p.name for p in (dep / 'sources').rglob('*.move')) != sorted(p.name for p in frozen_sources.rglob('*.move')):
            raise ValueError('Selected dependency module set differs from frozen graph: ' + str(dep))
        for path in (dep / 'sources').glob('*.move'):
            frozen = root / 'packages' / dep.name / 'sources' / path.name
            if not frozen.exists():
                frozen_name = 'soulidity_standard' if dep == standard else 'soulidity_foundation'
                frozen = root / 'packages' / frozen_name / 'sources' / path.name
            if not frozen.exists() or path.read_bytes() != frozen.read_bytes():
                raise ValueError('Selected dependency source differs from frozen graph: ' + str(path))
    run = root / 'evidence/verifier-runs' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
    graph = run / 'graph'
    graph.mkdir(parents=True)
    copy_package(package, graph / 'content')
    copy_package(standard, graph / 'soulidity_standard')
    copy_package(foundation, graph / 'soulidity_foundation')
    for name in ['sui-framework', 'move-stdlib', 'walrus', 'wal']:
        copy_package(root / 'offline-vendor' / name, graph / name, with_tests=True)
    diffs = []
    sui = '{ local = "../sui-framework", override = true }'
    rewrite_dependencies(graph / 'content', {'SoulidityStandard': '{ local = "../soulidity_standard" }', 'SoulidityFoundation': '{ local = "../soulidity_foundation" }', 'Sui': sui, 'Walrus': '{ local = "../walrus" }'}, diffs)
    for name in ['soulidity_standard', 'soulidity_foundation', 'walrus', 'wal']:
        rewrite_dependencies(graph / name, {'Sui': sui}, diffs)
    for name in ['sui-framework', 'move-stdlib']:
        if 'git =' in (graph / name / 'Move.toml').read_text():
            raise ValueError('Unexpected remote dependency in frozen framework')
    (run / 'offline-manifest.diff').write_text(''.join(diffs))
    input_rows = [{'path': str(p.relative_to(graph)), 'sha256': sha(p.read_bytes())} for p in sorted(graph.rglob('*')) if p.is_file()]
    write_json(run / 'graph-input-freeze.json', {'source_package': str(package), 'cli_sha256': CLI_SHA, 'files': input_rows, 'Sui_override': 'Exact original effective 2a0becb2fcc6989e492981104af67f62f2c9511a source; vendored Walrus/WAL manifest testnet-v1.51.1 is overridden just as in original CONTENT manifest'})
    print(str(run), flush=True)
    build_code = command(args.cli, ['move', 'build', '--path', str(graph / 'content'), '--install-dir', str(run / 'production-build')], run, 'production')
    summary = {'source_package': str(package), 'run': str(run), 'content_root_modules': 9, 'production_exit_code': build_code, 'no_remote_graph_dependencies': True, 'default_budget_unchanged': True, 'actual_unit_tests': 0, 'actual_unit_passed': 0, 'actual_unit_failed': None, 'no_consumer_or_chain_cutover': True, 'not_legacy_published_type_compatibility': True}
    if build_code:
        write_json(run / 'evidence.json', summary)
        return build_code
    spec = importlib.util.spec_from_file_location('bytecode_reader', root / 'tools/verify_contract_publication_budget.py')
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    comparisons = []
    compiled = run / 'production-build/build/SoulidityContent/bytecode_modules'
    for name in NINE:
        before = (root / 'evidence/compiler-production-baseline' / (name + '.mv')).read_bytes()
        after = (compiled / (name + '.mv')).read_bytes()
        bn, bh = normalized_addresses(before, reader)
        an, ah = normalized_addresses(after, reader)
        comparisons.append({'module': name, 'baseline_raw_sha256': sha(before), 'new_raw_sha256': sha(after), 'raw_equal': before == after, 'address_table_normalized_equal': bn == an, 'baseline_handles': bh, 'new_handles': ah})
    write_json(run / 'compiled-address-review.json', {'normalization': 'Only bytecode address table values for unambiguously matched Content/Standard/Foundation/Walrus/WAL module roles are replaced; no functions, structs, constants or instructions changed', 'modules': comparisons, 'all_normalized_equal': all(r['address_table_normalized_equal'] for r in comparisons), 'changed_raw_modules': sum(not r['raw_equal'] for r in comparisons), 'identity_limit': 'Address normalization is comparison evidence only. It does not make new package/type/linkage compatible with old published identities.'})
    shutil.copytree(root / 'packages/soulidity_content/tests', graph / 'content/tests')
    test_code = command(args.cli, ['move', 'test', '--path', str(graph / 'content'), '--install-dir', str(run / 'test-build')], run, 'unit')
    output = (run / 'unit.stdout.log').read_text()
    match = re.search(r'Total tests: (\d+); passed: (\d+); failed: (\d+)', output)
    summary['unit_exit_code'] = test_code
    if match:
        summary['actual_unit_tests'], summary['actual_unit_passed'], summary['actual_unit_failed'] = map(int, match.groups())
    summary['all_normalized_root_modules_equal'] = all(r['address_table_normalized_equal'] for r in comparisons)
    summary['verified'] = test_code == 0 and summary['actual_unit_tests'] == 19 and summary['actual_unit_passed'] == 19 and summary['actual_unit_failed'] == 0 and summary['all_normalized_root_modules_equal']
    summary['test_provenance'] = 'Original storage_epoch12 and pure capacity7; exact namespace/fixture adaptation and original hashes are in evidence/test-provenance.json. No Core/Native/paid-access whole journey is claimed.'
    write_json(run / 'evidence.json', summary)
    print(json.dumps(summary), flush=True)
    return 0 if summary['verified'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(2)
