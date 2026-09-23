**FREE
// DCL-S takes any of its keywords, in any combination.
//
// The DCL-S grammar paired each type with a hand-picked subset of
// keywords, so INZ on a ZONED, INZ on an array, a CHAR DIM(*VAR), or any
// combination nobody had spelled out was a syntax error. The initial
// value is also held to the declaration now, as an assigned one is. (An
// initial value longer than a CHAR field is an error, as on IBM i: test 256.)
DCL-S z    ZONED(7:2) INZ(12.345);
DCL-S c5   CHAR(5) INZ('ABC');
DCL-S ca   CHAR(3) DIM(3) INZ('X');
DCL-S na   PACKED(5:2) DIM(2) INZ(1.5);
DCL-S cv   CHAR(2) DIM(*VAR:5);
DCL-S ua   UNS(5) DIM(2) INZ(9);
DCL-S srt  INT(10) DIM(3) ASCEND INZ(0);

DCL-PR Count INT(10);
END-PR;

DSPLY ('RESULT:ZONED=' + %CHAR(z));
DSPLY ('RESULT:CHARFIT=[' + c5 + ']');
DSPLY ('RESULT:CHARARR=[' + ca(1) + '][' + ca(3) + ']');
DSPLY ('RESULT:NUMARR=' + %CHAR(na(2)) + ' ' + %CHAR(ua(1)));

// A varying CHAR array's new elements are blanks.
%ELEM(cv) = 2;
DSPLY ('RESULT:VARARR=[' + cv(2) + '] ' + %CHAR(%ELEM(cv)));

srt(1) = 3;
srt(2) = 1;
srt(3) = 2;
SORTA srt;
DSPLY ('RESULT:ASCEND=' + %CHAR(srt(1)) + %CHAR(srt(2)) + %CHAR(srt(3)));

// STATIC with INZ: initialized once, kept across calls.
Count();
Count();
DSPLY ('RESULT:STATIC=' + %CHAR(Count()));

*INLR = *ON;
RETURN;

DCL-PROC Count;
  DCL-PI *N INT(10);
  END-PI;
  DCL-S n INT(10) STATIC INZ(100);
  n = n + 1;
  RETURN n;
END-PROC;
