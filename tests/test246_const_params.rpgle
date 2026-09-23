**FREE
// CONST parameters.
//
// CONST was a syntax error: the parameter grammar spelled out one
// alternative per type x keyword combination, and none had CONST. It is
// the most common parameter keyword in modern code: the callee may not
// change it, so the caller may pass a literal or an expression, and the
// callee sees a value of the declared type (CHAR(10) CONST passed 'AB'
// holds 'AB' plus eight blanks).
DCL-DS pt QUALIFIED;
  x INT(10);
  y INT(10);
END-DS;

DCL-S name CHAR(10) INZ('VARIABLE');
DCL-S amt  PACKED(7:2) INZ(10);
DCL-S cnt  INT(10) INZ(0);

DCL-PR Show VARCHAR(40);
  s CHAR(10) CONST;
END-PR;
DCL-PR Cents INT(10);
  p PACKED(7:2) CONST;
END-PR;
DCL-PR Square INT(10);
  n INT(10) CONST;
END-PR;
DCL-PR SumPt INT(10);
  q LIKEDS(pt) CONST;
END-PR;
DCL-PR ShowZ VARCHAR(20);
  z ZONED(5:1) VALUE;
END-PR;
DCL-PR Maybe INT(10);
  c INT(10) VALUE OPTIONS(*NOPASS);
END-PR;

DSPLY ('RESULT:LIT=' + Show('AB'));
DSPLY ('RESULT:VAR=' + Show(name));
DSPLY ('RESULT:EXPR=' + %CHAR(Cents(amt * 0.1239)));
DSPLY ('RESULT:CALC=' + %CHAR(Square(3 + 4)));
pt.x = 3;
pt.y = 4;
DSPLY ('RESULT:LIKEDS=' + %CHAR(SumPt(pt)));
DSPLY ('RESULT:ZONED=' + ShowZ(12.34));
// OPTIONS(*NOPASS) with no argument at all used to generate M(, 0, 0).
DSPLY ('RESULT:NOPASS=' + %CHAR(Maybe(cnt)) + ' ' + %CHAR(Maybe()));

*INLR = *ON;
RETURN;

DCL-PROC Show;
  DCL-PI *N VARCHAR(40);
    s CHAR(10) CONST;
  END-PI;
  RETURN '[' + s + ']';
END-PROC;

DCL-PROC Cents;
  DCL-PI *N INT(10);
    p PACKED(7:2) CONST;
  END-PI;
  RETURN p * 100;
END-PROC;

DCL-PROC Square;
  DCL-PI *N INT(10);
    n INT(10) CONST;
  END-PI;
  RETURN n * n;
END-PROC;

DCL-PROC SumPt;
  DCL-PI *N INT(10);
    q LIKEDS(pt) CONST;
  END-PI;
  RETURN q.x + q.y;
END-PROC;

DCL-PROC ShowZ;
  DCL-PI *N VARCHAR(20);
    z ZONED(5:1) VALUE;
  END-PI;
  RETURN %CHAR(z);
END-PROC;

DCL-PROC Maybe;
  DCL-PI *N INT(10);
    c INT(10) VALUE OPTIONS(*NOPASS);
  END-PI;
  RETURN %PARMS();
END-PROC;
