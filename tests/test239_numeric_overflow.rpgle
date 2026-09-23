**FREE
// A numeric value too big for its target raises status 103, and division
// by zero raises 102.
//
// EVAL of 123456 into a PACKED(5:0) stored 123456, a value the field
// cannot hold; on IBM i it is error RNX0103 and the target is unchanged.
// Division by zero produced inf and carried on. Both are now catchable by
// MONITOR, with %STATUS set.
DCL-S p5   PACKED(5:0) INZ(7);
DCL-S p52  PACKED(5:2);
DCL-S n    INT(10);
DCL-S u    UNS(10);
DCL-S a    PACKED(5:0) INZ(10);
DCL-S zero PACKED(5:0) INZ(0);
DCL-S q    PACKED(9:2);

DCL-PR Big PACKED(3:0);
END-PR;
DCL-PR Take;
  v PACKED(3:0) VALUE;
END-PR;

// Too many integer digits: 103, and the target keeps its value.
MONITOR;
  p5 = 123456;
  DSPLY 'RESULT:P5=stored';
ON-ERROR;
  DSPLY ('RESULT:P5=' + %CHAR(%STATUS()) + ' kept ' + %CHAR(p5));
ENDMON;

// Excess decimals are truncated, not an overflow: 999.999 fits as 999.99.
p52 = 999.999;
DSPLY ('RESULT:FITS=' + %CHAR(p52));

// But 1000 does not fit a PACKED(5:2), and neither does 999.995 half-adjusted.
MONITOR;
  p52 = 1000;
  DSPLY 'RESULT:P52=stored';
ON-ERROR;
  DSPLY ('RESULT:P52=' + %CHAR(%STATUS()));
ENDMON;
MONITOR;
  EVAL(H) p52 = 999.995;
  DSPLY 'RESULT:HALF=stored';
ON-ERROR;
  DSPLY ('RESULT:HALF=' + %CHAR(%STATUS()));
ENDMON;

// Integer and unsigned ranges.
MONITOR;
  n = 3000000000;
  DSPLY 'RESULT:INT=stored';
ON-ERROR;
  DSPLY ('RESULT:INT=' + %CHAR(%STATUS()));
ENDMON;
MONITOR;
  u = -1;
  DSPLY 'RESULT:UNS=stored';
ON-ERROR;
  DSPLY ('RESULT:UNS=' + %CHAR(%STATUS()));
ENDMON;

// A RETURN value and a VALUE parameter are assigned the same way.
MONITOR;
  q = Big();
  DSPLY 'RESULT:RETURN=stored';
ON-ERROR;
  DSPLY ('RESULT:RETURN=' + %CHAR(%STATUS()));
ENDMON;
MONITOR;
  CALLP Take(5000);
  DSPLY 'RESULT:VALUE=passed';
ON-ERROR;
  DSPLY ('RESULT:VALUE=' + %CHAR(%STATUS()));
ENDMON;

// Division by zero: 102, for / and %DIV alike. The divisor is a field:
// a literal 0 is a compile-time error (IBM RNF0552; see test 255).
MONITOR;
  q = a / zero;
  DSPLY 'RESULT:DIV=stored';
ON-ERROR;
  DSPLY ('RESULT:DIV=' + %CHAR(%STATUS()));
ENDMON;
MONITOR;
  n = %DIV(10 : zero);
  DSPLY 'RESULT:PDIV=stored';
ON-ERROR;
  DSPLY ('RESULT:PDIV=' + %CHAR(%STATUS()));
ENDMON;

// Ordinary arithmetic is unaffected.
q = a / 4;
DSPLY ('RESULT:OK=' + %CHAR(q));

*INLR = *ON;
RETURN;

DCL-PROC Big;
  DCL-PI Big PACKED(3:0);
  END-PI;
  RETURN 1234;
END-PROC;

DCL-PROC Take;
  DCL-PI Take;
    v PACKED(3:0) VALUE;
  END-PI;
  DSPLY ('RESULT:TOOK=' + %CHAR(v));
END-PROC;
