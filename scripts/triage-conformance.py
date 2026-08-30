#!/usr/bin/env python3
"""Buckets the conformance rejections by what they actually mean.

The raw accepted/rejected count conflates unrelated things: missing IBM i
objects, genuine rpgc leniency, tests that were never valid standalone
programs, and negative tests where IBM rejecting is the CORRECT outcome.
Only bucket B is a work queue; bucket D is partly a pass.

Usage: scripts/triage-conformance.py [transcript] [--files]
"""
import re, sys, os, collections

log = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') \
      else 'ibmi-conformance-transcript.txt'
show_files = '--files' in sys.argv

lines = open(log, errors='replace').read().split('\n')
cur, buf, res = None, [], []
for ln in lines:
    if ln.startswith('@@@FILE '):
        if cur: res.append((cur, buf, 1))
        cur, buf = ln[8:].strip(), []
    elif ln.startswith('@@@RC ') and cur:
        res.append((cur, buf, int(ln[6:].strip() or 1))); cur, buf = None, []
    elif cur is not None:
        buf.append(ln)

MSG = re.compile(r'^\s*\*?(RN[SF]\d{4})\s+(\d+)')
SQLM = re.compile(r'^(SQL\d{4})\s+(\d+)')
accepted, rejected = [], []
for name, out, rc in res:
    codes = {m.group(1) for l in out for m in [MSG.match(l)] if m and int(m.group(2)) >= 20}
    sqls  = {m.group(1) for l in out for m in [SQLM.match(l)] if m and int(m.group(2)) >= 30}
    bad = any(re.match(r'^\s+(Error|Severe Error)\s+\(\d+\+?\).*:\s*[1-9]', l) for l in out)
    (rejected if (rc != 0 or bad) else accepted).append((name, codes, sqls))

# classification by diagnostic family
DEP    = {'RNF2120','RNF7030','RNF7503','RNF2121','RNF2109','RNF7080'}
STRUCT = {'RNF7023','RNF0257','RNF0724','RNF0256','RNF0258','RNF1501','RNF1502','RNF1508','RNF7031'}
LENIENT= {'RNF0372','RNF5261','RNF5347','RNF5014','RNF5375','RNF5001','RNF2093','RNF2367',
          'RNF0263','RNF2003','RNF2006','RNF4008','RNF4071','RNF6005','RNF0289','RNF5005',
          'RNF7016','RNF0637','RNF5377','RNF0622','RNF3308','RNF0592','RNF0597','RNF5343'}

B = collections.OrderedDict()
for k in ['A. needs IBM i objects','B. rpgc leniency (WORK QUEUE)',
          'C. not a valid standalone program','D. negative test (rejection may be CORRECT)',
          'E. SQL blocked (decimal-comma locale)','F. needs individual review']:
    B[k] = []

for name, codes, sqls in rejected:
    src = os.path.join('tests', name)
    body = open(src, encoding='utf-8', errors='replace').read().upper() if os.path.exists(src) else ''
    is_neg = ('_ERR' in name.upper()) or re.match(r'test11[a-e]', name)
    if sqls or (not codes and 'EXEC SQL' in body):
        B['E. SQL blocked (decimal-comma locale)'].append((name, sorted(sqls)[:3]))
    elif is_neg:
        B['D. negative test (rejection may be CORRECT)'].append((name, sorted(codes)[:3]))
    elif codes & LENIENT:
        B['B. rpgc leniency (WORK QUEUE)'].append((name, sorted(codes & LENIENT)[:3]))
    elif codes & DEP and any(k in body for k in ('DTAARA(','EXTDESC(','DCL-F ','WORKSTN')):
        B['A. needs IBM i objects'].append((name, sorted(codes & DEP)[:3]))
    elif codes & STRUCT:
        B['C. not a valid standalone program'].append((name, sorted(codes & STRUCT)[:3]))
    else:
        B['F. needs individual review'].append((name, sorted(codes)[:3]))

print(f"accepted {len(accepted)} / {len(res)}     rejected {len(rejected)}\n")
w = max(len(k) for k in B)
for k, v in B.items():
    print(f"  {k:<{w}}  {len(v):>3}")
if show_files:
    for k, v in B.items():
        if not v: continue
        print(f"\n{'='*72}\n{k}  ({len(v)})\n{'='*72}")
        for n, c in sorted(v):
            print(f"  {n:<48} {','.join(c)}")
