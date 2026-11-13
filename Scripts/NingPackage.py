#!/usr/bin/env python3
"""Package the original Sileo iOS layout; no installation or repository publication."""
import argparse,hashlib,io,json,os,plistlib,shutil,stat,struct,subprocess,tarfile,gzip
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(*args): subprocess.run([str(a) for a in args],check=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def tar_bytes(entries):
 stream=io.BytesIO()
 with tarfile.open(fileobj=stream,mode='w',format=tarfile.USTAR_FORMAT) as t:
  for name,data,mode,link in entries:
   info=tarfile.TarInfo(name); info.uid=0; info.gid=0; info.uname='root'; info.gname='wheel'; info.mtime=0; info.mode=mode
   if link is not None: info.type=tarfile.SYMTYPE; info.linkname=link
   else: info.size=len(data)
   t.addfile(info,io.BytesIO(data) if link is None else None)
 return gzip.compress(stream.getvalue(),compresslevel=9,mtime=0)
def ar(members):
 result=bytearray(b'!<arch>\n')
 for name,data in members:
  head=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode()
  assert len(head)==60
  result.extend(head); result.extend(data)
  if len(data)%2: result.extend(b'\n')
 return bytes(result)
def macho_files(app):
 for p in app.rglob('*'):
  if p.is_file() and not p.is_symlink() and p.read_bytes()[:4] in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe'):
   yield p
if __name__=='__main__':
 parser=argparse.ArgumentParser(); parser.add_argument('--app',required=True); args=parser.parse_args()
 out=ROOT/'packages'; out.mkdir(exist_ok=True)
 work=ROOT/'build'/'NingPackage'; work.mkdir(parents=True,exist_ok=True)
 app=work/'Sileo.app'; shutil.copytree(args.app,app,dirs_exist_ok=True,symlinks=True)
 plist_path=app/'Info.plist'
 with plist_path.open('rb') as f: info=plistlib.load(f)
 info['CFBundleShortVersionString']='2.5.1'; info['CFBundleVersion']=os.environ.get('GITHUB_RUN_NUMBER','1')
 with plist_path.open('wb') as f: plistlib.dump(info,f)
 helper=app/'giveMeRoot'
 run('xcrun','--sdk','iphoneos','clang','-arch','arm64','-mios-version-min=13.0','-O2','-Wall',ROOT/'giveMeRoot/giveMeRoot.c','-o',helper)
 # Sign nested code before the main executable, preserving upstream entitlements.
 binaries=list(macho_files(app)); main=app/info['CFBundleExecutable']; assert main in binaries and helper in binaries
 for p in binaries:
  if p==main: continue
  if p==helper: run('ldid','-S'+str(ROOT/'giveMeRoot/Entitlements.plist'),p)
  else: run('ldid','-S',p)
 run('ldid','-S'+str(ROOT/'Sileo/Entitlements.entitlements'),main)
 # Detached Xcode signatures refer to the unsigned application. ldid signs code,
 # and the deb has deterministic permissions independent of sandbox chmod.
 for p in list(app.rglob('_CodeSignature')):
  if p.is_dir(): shutil.rmtree(p)
 license_dir=app/'Ning-Licenses'; license_dir.mkdir(exist_ok=True)
 shutil.copy2(ROOT/'LICENSE',license_dir/'Sileo-LICENSE.txt')
 shutil.copy2(ROOT/'NING.md',license_dir/'Ning-modifications.txt')
 payload=[]; executable_names=set(binaries)
 for p in sorted(app.rglob('*')):
  if p.is_dir() and not p.is_symlink(): continue
  name='Applications/Sileo.app/'+p.relative_to(app).as_posix()
  if p.is_symlink(): payload.append((name,b'',0o777,os.readlink(p)))
  else: payload.append((name,p.read_bytes(),0o4755 if p==helper else (0o755 if p in executable_names else 0o644),None))
 version='2.5.1+ning.1'
 depends='firmware (>= 13.0), coreutils (>= 8.30-1), dpkg (>= 1.19.4-1), apt (>= 1.8.2), libzstd1'
 control='\n'.join(['Package: org.coolstar.sileo','Name: Sileo','Version: '+version,
  'Author: Ning&Amy While','Maintainer: Ning&Amy While','Description: Sileo with Ning ThemeBoard-style floating glass dock',
  'Architecture: iphoneos-arm','Depends: '+depends,'Section: Packaging',
  'Icon: https://getsileo.app/img/icon.png','Homepage: https://github.com/SorenNing/sileo',''])
 controls=[('control',control.encode(),0o644,None)]
 for name,source in [('postinst','postinst.in'),('prerm','prerm'),('triggers','triggers')]:
  data=(ROOT/'layout/DEBIAN'/source).read_bytes().replace(b'@@SILEO_APP@@',b'Sileo.app')
  controls.append((name,data,0o755 if name!='triggers' else 0o644,None))
 deb=out/f'org.coolstar.sileo_{version}_iphoneos-arm.deb'
 deb.write_bytes(ar([('debian-binary',b'2.0\n'),('control.tar.gz',tar_bytes(controls)),('data.tar.gz',tar_bytes(payload))]))
 report={'repository':os.environ.get('GITHUB_REPOSITORY'),'source_commit':os.environ.get('GITHUB_SHA'),
  'run_id':os.environ.get('GITHUB_RUN_ID'),'run_attempt':os.environ.get('GITHUB_RUN_ATTEMPT'),
  'version':version,'architecture':'arm64','layout':'Applications/Sileo.app (standard/rootful; NOT a native RootHide build)',
  'deb':deb.name,'size':deb.stat().st_size,'sha256':sha(deb),'main_sha256':sha(main),'helper_sha256':sha(helper),
  'payload_files':len(payload),'installed_or_runtime_tested':False}
 for p in binaries:
  data=p.read_bytes(); assert data[:4]==b'\xcf\xfa\xed\xfe',p
  cpu,sub=struct.unpack_from('<II',data,4); assert cpu==0x100000c,(p,cpu)
  if p==main: report['main_cpu_subtype']=hex(sub)
 # Re-open our actual data stream, validate helper setuid and program bytes.
 with tarfile.open(fileobj=io.BytesIO(tar_bytes(payload)),mode='r:gz') as t:
  h=t.getmember('Applications/Sileo.app/giveMeRoot'); assert h.mode==0o4755
  assert t.extractfile('Applications/Sileo.app/'+info['CFBundleExecutable']).read()==main.read_bytes()
 (out/'receipt.json').write_text(json.dumps(report,indent=2)+'\n')
 (out/'SHA256SUMS').write_text(sha(deb)+'  '+deb.name+'\n')
 print(json.dumps(report,indent=2))
