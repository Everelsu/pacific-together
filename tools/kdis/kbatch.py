"""List every Blueprint-like .uasset under a folder into outdir/<name>.txt. Usage: python -I kbatch.py srcdir outdir"""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kdis import listing

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
n = bad = 0
for root, _, files in os.walk(src):
    for f in files:
        p = os.path.join(root, f)
        if not f.endswith('.uasset') or not os.path.exists(p[:-6] + 'uexp'): continue
        if not re.match(r'(BP_|UMG_|BPMT_|Minimap|W_|BFL_|AC_|PDP_|IP_|OBJ_)', f): continue
        try: lines = list(listing(p))
        except Exception as ex: lines = [f'!! file {ex}']
        bad += sum(1 for l in lines if l.lstrip().startswith('!!'))
        open(os.path.join(out, f[:-7] + '.txt'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        n += 1
print(n, 'files', bad, 'errors')
