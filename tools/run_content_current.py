#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'evidence/content-current-kinds/verification-config.json'
if len(sys.argv)!=1:raise ValueError('No arguments accepted')
if hashlib.sha256(p.read_bytes()).hexdigest()!='8ee2012260bd454f19fdf55b534b64320dc83806dd4fa7c6aed505460d965b12':raise ValueError('Reviewed config changed')
c=json.loads(p.read_text());binary=Path(c['python'])
if hashlib.sha256(binary.read_bytes()).hexdigest()!=c['python_sha256']:raise ValueError('Pinned Python changed')
os.execv(str(binary),[str(binary),str(root/'tools/verify_content_current.py'),'--config',str(p)])
