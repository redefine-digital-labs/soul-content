#!/usr/bin/env python3
"""Verify current independent Content9 and its unchanged original19 tests."""
import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def put(p, data):
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--candidate', action='store_true')
    args = parser.parse_args()
    config_path = args.config.resolve()
    seal = json.loads(config_path.with_name('verification-seal.json').read_text())
    require(sha(config_path) == seal['config_sha256'], 'Config changed')
    for p, digest in seal['controls'].items():
        require(sha(p) == digest, 'Control changed: ' + p)
    cfg = json.loads(config_path.read_text())
    require(Path(sys.executable).resolve() == Path(cfg['python']) and sha(cfg['python']) == cfg['python_sha256'], 'Wrong fixed Python runtime')
    require(sha(cfg['sui']) == cfg['sui_sha256'], 'Wrong fixed Sui tool')
    spec = importlib.util.spec_from_file_location('content_lock_graph', cfg['lock_helper'])
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    roots = {name: Path(row['candidate'] if args.candidate else row['actual']) for name,row in cfg['roots'].items()}
    rows = cfg['inputs']
    def pins():
        result = {}
        for name, root in roots.items():
            paths = [root/'Move.toml',root/'Move.lock',*sorted((root/'sources').glob('*.move'))]
            if name == 'soulidity_content':
                paths += sorted((root/'tests').glob('*.move'))
            for p in paths:
                result[(name,str(p.relative_to(root)))] = sha(p)
        return result
    before = pins()
    require(before == {(r['root'],r['relative']):r['candidate_sha256' if args.candidate else 'actual_sha256'] for r in rows}, 'Installed root source/manifest/lock/test inputs changed')
    require(len([r for r in rows if r['root']=='soulidity_content' and r['relative'].startswith('sources/')]) == 9, 'Content must have nine owned modules')
    controls = {str(p):sha(p) for p in [config_path,config_path.with_name('verification-seal.json'),Path(cfg['python']),Path(cfg['sui']),*[Path(p) for p in seal['controls']]]}
    def cache_pins():
        return {str(p):sha(p) for root in cfg['cache_roots'] for p in sorted(Path(root).rglob('*')) if p.is_file() and (p.suffix=='.move' or p.name in ['Move.toml','Move.lock'])}
    cache_before=cache_pins()
    require(cache_before==cfg['cache_inputs'],'Selected framework/Walrus compiler inputs changed')
    output = config_path.parent/'runs'/str(time.time_ns())
    output.mkdir(parents=True)
    put(output/'controls-before.json',controls)
    put(output/'cache-before.json',cache_before)
    staged = {k:output/'staged'/k for k in roots}
    mapping = {str(roots[k]):str(staged[k]) for k in roots}
    manifests = {str(r):(r/'Move.toml').read_text() for r in roots.values()}
    names = {str(roots[k]):v['package'] for k,v in cfg['roots'].items()}
    checks = helper.check_lock(roots['soulidity_content'],names)
    put(output/'source-lock-checks.json',checks)
    for r in rows:
        name,relative=r['root'],r['relative']
        src,dst=roots[name]/relative,staged[name]/relative
        dst.parent.mkdir(parents=True,exist_ok=True)
        if relative=='Move.toml':
            dst.write_text(helper.replace_locators(src.read_text(),mapping))
        elif relative=='Move.lock':
            dst.write_text(helper.retarget_lock(src.read_text(),roots[name],manifests,mapping))
        else:
            shutil.copyfile(src,dst)
            require(sha(dst)==sha(src),'Staged source bytes changed')
    stage_before={str(p):sha(p) for r in staged.values() for p in r.rglob('*') if p.is_file()}
    put(output/'staged-inputs-before.json',stage_before)
    put(output/'inputs-before.json',[{'root':k,'relative':r,'sha256':v} for (k,r),v in before.items()])
    put(output/'stage-lock-checks.json',helper.check_lock(staged['soulidity_content'],{str(staged[k]):v['package'] for k,v in cfg['roots'].items()}))
    results=[]
    for operation in ['build','test']:
        install=output/'scratch'
        cmd=[cfg['sui'],'move',operation,'--path',str(staged['soulidity_content']),'--install-dir',str(install)]
        if operation=='build':cmd+=['--dump-bytecode-as-base64','--with-unpublished-dependencies','--no-tree-shaking']
        run=subprocess.run(cmd,capture_output=True)
        stdout,stderr=output/(operation+'.stdout'),output/(operation+'.stderr')
        stdout.write_bytes(run.stdout);stderr.write_bytes(run.stderr)
        row={'operation':operation,'command':cmd,'exit':run.returncode,'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr),'gas_limit_override':None}
        require(run.returncode==0,'Current Content '+operation+' failed; raw logs: '+str(output))
        if operation=='build':
            modules={p.name:sha(p) for p in (install/'build/SoulidityContent/bytecode_modules').glob('*.mv')}
            require(modules==cfg['expected_content9_modules'],'Independent Content9 module bytes differ from current integrated twelve-source Content')
            row['nine_module_bytes_equal_integrated_current']=True
            put(output/'content9.modules.json',modules)
        else:
            text=(run.stdout+run.stderr).decode(errors='replace')
            match=re.search(r'Total tests:\s*(\d+);\s*passed:\s*(\d+);\s*failed:\s*(\d+)',text)
            row['counts']=list(map(int,match.groups())) if match else None
            require(row['counts']==[19,19,0],'Original Content19 count/failure mismatch')
        require(pins()==before and all(sha(p)==v for p,v in controls.items()) and all(sha(p)==v for p,v in stage_before.items()) and cache_pins()==cache_before,'Source/control/cache drift during verification')
        results.append(row);put(output/'results.json',results)
        if install.exists():shutil.rmtree(install)
    put(output/'inputs-after.json',[{'root':k,'relative':r,'sha256':v} for (k,r),v in pins().items()])
    put(output/'staged-inputs-after.json',{str(p):sha(p) for r in staged.values() for p in r.rglob('*') if p.is_file()})
    put(output/'controls-after.json',{p:sha(p) for p in controls})
    put(output/'cache-after.json',cache_pins())
    put(output/'summary.json',{'status':'PASS','scope':'staged frozen Content9 candidate' if args.candidate else 'staged actual independent Content9 inputs','config_sha256':sha(config_path),'input_files':len(rows),'selected_cache_files':len(cache_before),'source_path_executed':False,'nine_module_bytes_equal_integrated_current':True,'original_content_tests':[19,19,0],'inputs_and_controls_unchanged':True,'cache_unchanged':True,'results':results,'rpc_calls':0,'signatures':0,'published_compatibility_proven':False})
    print(json.dumps({'status':'PASS','evidence':str(output),'tests':19}))


if __name__=='__main__':main()
