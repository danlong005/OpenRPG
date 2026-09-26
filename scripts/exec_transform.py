"""Route every DSPLY in an RPG source to a message queue, so a program run on
IBM i leaves its output somewhere it can be read back.

On IBM i, DSPLY posts to the job's external message queue, which dies with the
job: from an SSH session its output is unreachable. DSPLY takes an optional
second operand, the message queue to send to. Naming a queue in the current
library sends each message there instead, and the ibmi-execution harness reads
the queue back in order. Verified on PUB400 2026-09-26: free-form, fixed-form
and conditioned DSPLYs all accept the operand, and the text arrives exactly as
DSPLY formats it ("DSPLY  " followed by the message).

This is the ONLY change made to a source. Nothing about what is displayed is
touched, so what IBM shows is IBM's own DSPLY formatting (numeric editing
included), not a rewrite of it.

    from exec_transform import route_dsply
    text, n, problems = route_dsply(source_text)
"""
import re

MSGQ = "RPGCOUT"
OPERAND = f"'{MSGQ}'"

# Fixed-format C-spec columns (1-based): conditioning 9-11, Factor 1 12-25,
# operation 26-35, Factor 2 36-49, result 50-63.
OP, F2, RESULT = (25, 35), (35, 49), (49, 63)
# Code in a fixed-format source may not pass column 80.
FIXED_WIDTH = 80

DSPLY_FREE = re.compile(r'^(\s*)(dsply(?:\(\s*e\s*\))?)(?=[\s;(\'])', re.I)


def is_free(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip().upper().startswith('**FREE')
    return False


def _end_of_statement(lines, i, col):
    """(line, column) of the ';' ending the statement that starts at lines[i][col],
    skipping quoted literals and // comments, or None."""
    quote = False
    while i < len(lines):
        s = lines[i]
        j = col
        while j < len(s):
            ch = s[j]
            if quote:
                if ch == "'":
                    if j + 1 < len(s) and s[j + 1] == "'":
                        j += 1
                    else:
                        quote = False
            elif ch == "'":
                quote = True
            elif s.startswith('//', j):
                break
            elif ch == ';':
                return i, j
            j += 1
        i, col = i + 1, 0
    return None


def _top_level_space(expr):
    """True if expr has whitespace outside quotes and parentheses, i.e. would
    read as two operands once a queue operand follows it."""
    depth, quote = 0, False
    k = 0
    while k < len(expr):
        ch = expr[k]
        if quote:
            if ch == "'":
                if k + 1 < len(expr) and expr[k + 1] == "'":
                    k += 1
                else:
                    quote = False
        elif ch == "'":
            quote = True
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch.isspace() and depth == 0:
            return True
        k += 1
    return False


def route_dsply(text):
    """Return (new_text, dsply_count, problems). A non-empty problems list means
    the source could not be transformed faithfully and must not be run."""
    free = is_free(text)
    lines = text.split('\n')
    out = list(lines)
    problems, count = [], 0
    i = 0
    while i < len(lines):
        s = lines[i]
        # Fixed-format C-spec: 'C' in column 6, not a comment.
        if not free and len(s) > 6 and s[5] in 'Cc' and s[6] != '*':
            op = s[OP[0]:OP[1]].strip().upper()
            if re.fullmatch(r'DSPLY(\(E\))?', op):
                if s[RESULT[0]:RESULT[1]].strip():
                    problems.append(f"line {i+1}: DSPLY has a response field; it would wait for a reply")
                elif not s[F2[0]:F2[1]].strip():
                    padded = s.ljust(F2[0])
                    out[i] = padded[:F2[0]] + OPERAND.ljust(F2[1] - F2[0]) + padded[F2[1]:]
                    out[i] = out[i].rstrip()
                    count += 1
            i += 1
            continue
        # Free-form: a statement starting with DSPLY. In a fixed-format
        # source, free-form code sits at column 8 or later.
        body_from = 0 if free else 7
        if not free and (len(s) <= 7 or s[6] == '*' or s[5:7].strip()):
            i += 1
            continue
        m = DSPLY_FREE.match(s[body_from:])
        if not m:
            i += 1
            continue
        start = body_from + m.end()
        end = _end_of_statement(lines, i, start)
        if end is None:
            problems.append(f"line {i+1}: DSPLY has no terminating ';'")
            i += 1
            continue
        ei, ej = end
        if ei == i:
            expr = s[start:ej]
        else:
            expr = '\n'.join([s[start:]] + lines[i + 1:ei] + [lines[ei][:ej]])
        if not expr.strip():
            problems.append(f"line {i+1}: DSPLY has no message operand")
            i = ei + 1
            continue
        flat = ' '.join(expr.split())
        if _top_level_space(flat):
            # Parenthesize so the queue name cannot read as part of the message.
            # Same expression, so the same value and the same formatting.
            e = expr.strip()
            if not (e.startswith('(') and _matching_paren(e) == len(e) - 1):
                expr = expr.replace(e, '(' + e + ')', 1) if '\n' not in expr else \
                    re.sub(r'^(\s*)', r'\1(', expr, count=1) + ')'
        tail = lines[ei][ej:]
        new_end = expr.rstrip() + ' ' + OPERAND + tail
        head = s[:start]
        joined = head + new_end
        new_lines = joined.split('\n')
        if not free and max(len(l.split('//')[0].rstrip()) for l in new_lines) > FIXED_WIDTH:
            # Too long for a fixed-format line: the operand goes on its own line.
            indent = ' ' * (len(s) - len(s.lstrip()) + 2)
            new_lines = (head + expr.rstrip()).split('\n') + [indent + OPERAND + tail]
            if max(len(l) for l in new_lines[:-1]) > FIXED_WIDTH:
                problems.append(f"line {i+1}: DSPLY does not fit in {FIXED_WIDTH} columns once parenthesized")
                i = ei + 1
                continue
        out[i:ei + 1] = [None] * (ei + 1 - i)
        out[i] = '\n'.join(new_lines)
        count += 1
        i = ei + 1
    return '\n'.join(l for l in out if l is not None), count, problems


def _matching_paren(e):
    depth, quote = 0, False
    for k, ch in enumerate(e):
        if quote:
            if ch == "'":
                quote = False
        elif ch == "'":
            quote = True
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return k
    return -1


if __name__ == '__main__':
    import sys
    for p in sys.argv[1:]:
        t, n, probs = route_dsply(open(p, encoding='utf-8', errors='replace').read())
        print(f"{p}: {n} DSPLY routed" + (f"; PROBLEMS: {probs}" if probs else ''))
