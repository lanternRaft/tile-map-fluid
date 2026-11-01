"""Additional Stage 1 diagnostics. Run after stage1_trials.py, without concurrency."""
import importlib.util, json, pathlib, shutil, subprocess, sys
spec=importlib.util.spec_from_file_location('trials', pathlib.Path(__file__).with_name('stage1_trials.py'))
t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
root=t.root
# Plain checkouts contain no timer injection or autoload.
for variant, source in [('baseline',pathlib.Path('/tmp/tile-fluid-stage1-original')),('candidate',root)]:
 dst=pathlib.Path('/tmp/tile-fluid-stage1-plain-'+variant)
 shutil.copytree(source,dst,ignore=shutil.ignore_patterns('.git','.godot','reports'),dirs_exist_ok=True)
 shutil.copy(root/'tools/stage1_run.gd',dst/'tools/stage1_run.gd')
 with (t.out/variant/'plain-import.log').open('w') as log:
  subprocess.run(['godot','--headless','--path',str(dst),'--editor','--import','--quit'],stdout=log,stderr=subprocess.STDOUT,check=True)
 if variant=='baseline': t.base=dst
 else: t.candidate=dst
# Diagnostic scopes are identical on both sides; kept separate from acceptance timers.
plain_base,plain_candidate=t.base,t.candidate
for variant,source in [('baseline',pathlib.Path('/tmp/tile-fluid-stage1-original')),('candidate',root)]:
 dst=pathlib.Path('/tmp/tile-fluid-stage1-detail-'+variant)
 subprocess.run(['python3',str(root/'tools/stage1_prepare.py'),str(source),str(dst),'--detail'],check=True)
 shutil.copy(root/'tools/stage1_run.gd',dst/'tools/stage1_run.gd')
 with (t.out/variant/'detail-import.log').open('w') as log:
  subprocess.run(['godot','--headless','--path',str(dst),'--editor','--import','--quit'],stdout=log,stderr=subprocess.STDOUT,check=True)
 if variant=='baseline': t.base=dst
 else: t.candidate=dst
for variant in ['baseline','candidate']:
 t.run(variant,'detail-profile',['ticks=3600'])
t.base,t.candidate=plain_base,plain_candidate
for pair in range(3):
 for variant in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
  t.run(variant,f'edit-costs-{pair+1}',['ticks=240','edits=true','edit_repeats=10'])
for moving in [False,True]:
 for variant in ['baseline','candidate']:
  t.run(variant,'replay-'+str(moving).lower(),['ticks=1200','replay=true','hoses=2','moving='+str(moving).lower()])
 b=json.loads((t.out/'baseline'/('replay-'+str(moving).lower()+'.json')).read_text())
 c=json.loads((t.out/'candidate'/('replay-'+str(moving).lower()+'.json')).read_text())
 assert b['receiver_count']==c['receiver_count']==67,(b['receiver_count'],c['receiver_count'])
 assert b['replay']==c['replay'],'Every tick must match exactly: field SHA256, receiver floats, ordered signals and reentrant reads'
 print('EXACT REPLAY PASS',moving,len(b['replay']),flush=True)
for moving in [False,True]:
 for pair in range(3):
  for variant in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
   t.run(variant,f'plain-cpu-{moving}-{pair+1}',['ticks=3600','moving='+str(moving).lower()])
for speed in [1,8]:
 for variant in (['baseline','candidate'] if speed==1 else ['candidate','baseline']):
  t.run(variant,f'plain-sustained-{speed}x',['mode=rendered',f'speed={speed}','seconds='+('225' if speed==1 else '90'),'capture=true'],True)
