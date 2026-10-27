**FREE
// Program calls that fail: a program that can't be found is status 211,
// one that ends in an error is 202 in its caller, and one that returns
// with a halt indicator on is 231. Any of them can be handled, and the next call
// goes on as usual.
DCL-PR missing EXTPGM('NOSUCHPGM');
END-PR;
DCL-PR pgmFail EXTPGM('PGMFAIL');
  mode CHAR(1) CONST;
  n INT(10);
END-PR;
DCL-S n INT(10) INZ(1);

MONITOR;
  missing();
ON-ERROR 211;
  DSPLY ('not found: ' + %CHAR(%STATUS));
ENDMON;
CALLP(E) missing();
DSPLY ('CALLP(E): ' + %CHAR(%STATUS) + ' ' + %CHAR(%ERROR));

MONITOR;
  pgmFail('Z' : n);
ON-ERROR;
  DSPLY ('ended in error: ' + %CHAR(%STATUS));
ENDMON;
MONITOR;
  pgmFail('H' : n);
ON-ERROR;
  DSPLY ('halt indicator: ' + %CHAR(%STATUS));
ENDMON;
pgmFail('N' : n);
DSPLY ('normal: ' + %CHAR(n));
*INLR = *ON;
RETURN;
