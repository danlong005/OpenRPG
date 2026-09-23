**FREE
// Arrays start with their elements initialized.
//
// A standalone CHAR(n) DIM(m) was a bare std::array of empty strings, not
// n blanks per element. Worse, a numeric array declared inside a
// procedure was a local std::array with no initializer, so its elements
// held whatever was on the stack. Dirty() leaves 7s where Check()'s
// arrays will be, so that case fails deterministically rather than by luck.
DCL-S codes CHAR(3) DIM(2);

DCL-PR Dirty;
END-PR;
DCL-PR Check;
END-PR;

DSPLY ('RESULT:GLOBAL=[' + codes(1) + '][' + codes(2) + '] ' + %CHAR(%LEN(codes(2))));
CALLP Dirty();
CALLP Check();
*INLR = *ON;
RETURN;

DCL-PROC Dirty;
  DCL-PI Dirty;
  END-PI;
  DCL-S junk INT(10) DIM(64);
  DCL-S k    INT(10);
  FOR k = 1 TO 64;
    junk(k) = 7;
  ENDFOR;
  DSPLY ('RESULT:DIRTY=' + %CHAR(junk(64)));
END-PROC;

DCL-PROC Check;
  DCL-PI Check;
  END-PI;
  DCL-S nums INT(10) DIM(64);
  DCL-S k    INT(10);
  DCL-S sum  INT(10);
  DCL-S amts PACKED(7:2) DIM(3);
  DCL-S tags CHAR(2) DIM(3);
  sum = 0;
  FOR k = 1 TO 64;
    sum = sum + nums(k);
  ENDFOR;
  DSPLY ('RESULT:LOCALINT=' + %CHAR(sum));
  DSPLY ('RESULT:LOCALDEC=' + %CHAR(amts(3)));
  DSPLY ('RESULT:LOCALCHAR=[' + tags(3) + ']');
END-PROC;
