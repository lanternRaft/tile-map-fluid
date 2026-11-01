"""Sequential matched trials; outputs raw JSON and logs in the plan's artifact tree."""
import pathlib, subprocess, sys, time, resource, json
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'reports/benchmarks/architecture/stage1'
base=pathlib.Path('/tmp/tile-fluid-stage1-b')
candidate=pathlib.Path('/tmp/tile-fluid-stage1-c')
def run(variant, label, args, rendered=False):
 path=base if variant=='baseline' else candidate
 target=out/variant/(label+'.json')
 target.unlink(missing_ok=True)
 command=['godot','--path',str(path),'--audio-driver','Dummy','--script','tools/stage1_run.gd']
 if rendered: command += ['--rendering-method','gl_compatibility','--disable-vsync']
 else: command += ['--headless','--fixed-fps','120']
 command += ['--', 'out='+str(target)]+args
 print(time.strftime('%H:%M:%S'), variant,label,flush=True)
 before = resource.getrusage(resource.RUSAGE_CHILDREN)
 process_start = time.monotonic()
 with target.with_suffix('.log').open('w') as log:
  subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=240)
 after = resource.getrusage(resource.RUSAGE_CHILDREN)
 data = json.loads(target.read_text())
 data['child_cpu_seconds_including_setup_warmup'] = (after.ru_utime-before.ru_utime)+(after.ru_stime-before.ru_stime)
 data['child_wall_seconds_including_setup_warmup'] = time.monotonic()-process_start
 data['command'] = command
 target.write_text(json.dumps(data))
 if 'ERROR:' in target.with_suffix('.log').read_text():
  raise RuntimeError('Engine error: '+str(target))
if __name__ == '__main__':
 for case in ['stationary','moving']:
  for pair in range(3):
   for variant in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
    run(variant,f'cpu-{case}-{pair+1}',['ticks=3600','moving='+str(case=='moving').lower()])
 # A timing regression check alone is not evidence of improvement.
 gate = {}
 for case in ['stationary','moving']:
  for key in ['wettable_2d.gd:advance','addon_union']:
   samples = {}
   for variant in ['baseline','candidate']:
    samples[variant] = [json.loads((out/variant/f'cpu-{case}-{i}.json').read_text())['operations'][key][0]/3600 for i in [1,2,3]]
   b,c=samples['baseline'],samples['candidate']
   improvement=1-sum(c)/sum(b)
   noise=max((max(b)-min(b))/(sum(b)/3),(max(c)-min(c))/(sum(c)/3))
   paired=[1-y/x for x,y in zip(b,c)]
   gate[case+':'+key]={'baseline_us':b,'candidate_us':c,'improvement':improvement,'noise_spread':noise,'paired_improvements':paired,'passed':improvement>=0.05 and min(paired)>noise}
 (out/'cpu-gate.json').write_text(json.dumps(gate,indent=2))
 assert all(record['passed'] for record in gate.values()), 'CPU improvement gate failed; do not accept or continue sustained trials'
 for speed in [1,8]:
  for pair in range(3):
   for variant in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
    run(variant,f'rendered-{speed}x-{pair+1}',['mode=rendered',f'speed={speed}','seconds=30'],True)
