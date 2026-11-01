"""Summarize retained raw trials. No pass label is inferred from missing measurements."""
import json, pathlib, statistics, math
root=pathlib.Path(__file__).resolve().parents[1]/'reports/benchmarks/architecture/stage1'
def pct(values, p):
 values=sorted(values)
 return values[min(len(values)-1,max(0,math.ceil(len(values)*p)-1))] if values else None
rows=[]
for variant in ['baseline','candidate']:
 for path in sorted((root/variant).glob('*.json')):
  if not path.name.startswith(('cpu-', 'rendered-', 'sustained-', 'plain-', 'replay-', 'detail-')): continue
  d=json.loads(path.read_text()); f=d['frames_ms']; o=d.get('operations',{}); ticks=d['ticks']
  row={'variant':variant,'trial':path.stem,'ticks':ticks,'seconds':d['seconds'],'ticks_s':d['ticks_per_second'],
       'fps':len(f)/d['seconds'],'p50_ms':pct(f,.50),'p95_ms':pct(f,.95),'p99_ms':pct(f,.99),
       'worst_ms':max(f) if f else None,'over_8_33_fraction':sum(x>1000/120 for x in f)/len(f) if f else None,
       'simulated_seconds':ticks/120,'schedule_deficit_fraction':max(0,1-d['ticks_per_second']/(120*int(d['args'].get('speed','1')))) if d['args'].get('mode')=='rendered' else None,
       'child_cpu_seconds_including_setup_warmup':d.get('child_cpu_seconds_including_setup_warmup'),'steady_wall_ms_tick':d['seconds']*1000/ticks,'window_visible':d.get('window_visible'),'window_can_draw':d.get('window_can_draw'),'viewport_size':d.get('viewport_size'),
       'memory_bytes':d['memory'],'setup_ms':d.get('setup_usec',0)/1000}
  for key in ['wettable_2d.gd:advance','addon_union']:
   row[key+'_us_tick']=o[key][0]/ticks if key in o else None
   series=[t.get(key,0) for t in d.get('tick_operations',[])]
   row[key+'_p50_us']=pct(series,.5);row[key+'_p95_us']=pct(series,.95)
  rows.append(row)
(root/'summary.json').write_text(json.dumps(rows,indent=2))
for row in rows:
 print(row['variant'],row['trial'], 'wet/addon us', round(row['wettable_2d.gd:advance_us_tick'],2) if row['wettable_2d.gd:advance_us_tick'] is not None else 'unmeasured',round(row['addon_union_us_tick'],2) if row['addon_union_us_tick'] is not None else 'unmeasured',
       'FPS/Hz',round(row['fps'],1),round(row['ticks_s'],1),'p95/p99',row['p95_ms'],row['p99_ms'])
