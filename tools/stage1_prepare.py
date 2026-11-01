"""Create an isolated, equally instrumented measurement checkout. Never edits the input."""
import pathlib, shutil, sys, hashlib, json
src, dst = map(pathlib.Path, sys.argv[1:3])
shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.git', '.godot', 'reports'), dirs_exist_ok=True)
manifest = {str(p.relative_to(src)): hashlib.sha256(p.read_bytes()).hexdigest() for p in src.rglob('*') if p.is_file() and not any(x in p.relative_to(src).parts for x in ('.git','.godot','reports'))}
(dst/'source-manifest.json').write_text(json.dumps(manifest, indent=2))
# Scoped timers include all returns via a RefCounted scope guard. No per-call file I/O.
(dst/'tools/stage1_metrics.gd').write_text('''extends Node
var totals: Dictionary = {}
var depth: int = 0
var outer_start: int = 0
func reset() -> void:
\ttotals.clear()
func span(key: String) -> RefCounted:
\treturn Span.new(self, key)
class Span extends RefCounted:
\tvar owner: Node
\tvar key: String
\tvar start: int
\tfunc _init(target: Node, label: String) -> void:
\t\towner = target
\t\tkey = label
\t\tstart = Time.get_ticks_usec()
\t\tif owner.depth == 0:
\t\t\towner.outer_start = start
\t\towner.depth += 1
\tfunc _notification(what: int) -> void:
\t\tif what == NOTIFICATION_PREDELETE:
\t\t\tvar record: Array = owner.totals.get(key, [0, 0])
\t\t\trecord[0] += Time.get_ticks_usec() - start
\t\t\trecord[1] += 1
\t\t\towner.totals[key] = record
\t\t\towner.depth -= 1
\t\t\tif owner.depth == 0:
\t\t\t\tvar total: Array = owner.totals.get("addon_union", [0, 0])
\t\t\t\ttotal[0] += Time.get_ticks_usec() - owner.outer_start
\t\t\t\ttotal[1] += 1
\t\t\t\towner.totals["addon_union"] = total
''')
p=dst/'project.godot'; p.write_text(p.read_text()+'\n[autoload]\nStage1Metrics="*res://tools/stage1_metrics.gd"\n')
methods={'wettable_2d.gd':['advance','refresh_contact','_set_saturation','_apply_tint'], 'wet_surface_2d.gd':['validation_error','contains_world_point','_physics_process'], 'wet_surface_presentation.gd':['_process'], 'wet_grid_simulation.gd':['sample'], 'wet_surface_coverage.gd':['contains'], 'wet_field_patch.gd':['interpolate'], 'wet_body_traction.gd':['apply'], 'wettable_settings.gd':['validation_error'], 'water_spray_2d.gd':['advance']}
if '--detail' in sys.argv and 'func _sample_contact(' in (dst/'addons/tile_map_fluid/wet_surface_2d.gd').read_text():
 methods['wet_surface_2d.gd'].append('_sample_contact')
 methods['wet_grid_simulation.gd'].extend(['prepare_contact','_sample_contact_validated'])
if '--detail' not in sys.argv:
 methods = {'wettable_2d.gd':['advance'], 'water_spray_2d.gd':['advance'],
 'wet_surface_2d.gd':['_physics_process','saturation_at'],
 'wet_surface_presentation.gd':['_process'], 'receiver_proxy_2d.gd':['synchronize']}
if '--detail' not in sys.argv and 'func _sample_contact(' in (dst/'addons/tile_map_fluid/wet_surface_2d.gd').read_text():
 methods['wet_surface_2d.gd'].append('_sample_contact')
import re
for filename, names in methods.items():
 p=dst/'addons/tile_map_fluid'/filename
 if not p.exists(): continue
 s=p.read_text()
 for name in names:
  pat=r'(func '+re.escape(name)+r'\([^\n]*(?:\n[^\n]*)*?\)\s*->[^\n]+:\n)'
  # Signatures in this set are single-line.
  pat=r'(func '+re.escape(name)+r'\([^\n]*\)\s*->[^\n]+:\n)'
  s,n=re.subn(pat,lambda m:m[0]+'\tvar _stage1_span: RefCounted = Stage1Metrics.span("'+filename+':'+name+'")\n',s)
  assert n==1,(filename,name,n)
 p.write_text(s)
