**FREE
// Compound assignment: target op= value is target = target op (value).
DCL-S n INT(10) INZ(10);
DCL-S p PACKED(7:2) INZ(10);
DCL-S s VARCHAR(20) INZ('ab');
DCL-S arr INT(10) DIM(3);
DCL-DS ds QUALIFIED;
  tot PACKED(9:2);
END-DS;
DCL-S i INT(10) INZ(2);

n += 5;
DSPLY %CHAR(n);           // 15
n -= 3;
DSPLY %CHAR(n);           // 12
n *= 2 + 1;               // the value is one operand: n * (2 + 1)
DSPLY %CHAR(n);           // 36
n /= 4;
DSPLY %CHAR(n);           // 9
n **= 2;
DSPLY %CHAR(n);           // 81
s += 'cd';                // concatenation
DSPLY s;                  // abcd
arr(i) += 7;
arr(i) += 1;
DSPLY %CHAR(arr(2));      // 8
ds.tot += 1.25;
ds.tot += 1.25;
DSPLY %CHAR(ds.tot);      // 2.50
EVAL(H) p /= 3;           // half-adjusted
DSPLY %CHAR(p);           // 3.33
EVAL n -= 1;
DSPLY %CHAR(n);           // 80
*INLR = *ON;
