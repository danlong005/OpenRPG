**FREE
// A procedure call is a statement on its own: CALLP is optional in free
// form. proc(); and proc(a : b); parsed, but a one-argument proc(x); read
// like the start of an array-element assignment, arr(x) = ...;, and was a
// syntax error. Array-element assignments must of course still parse.
DCL-S total INT(10);
DCL-S arr   INT(10) DIM(3);
DCL-S i     INT(10) INZ(2);

DCL-DS rows QUALIFIED DIM(2);
  qty INT(10);
END-DS;

DCL-PR Add;
  v INT(10) VALUE;
END-PR;
DCL-PR AddTwo;
  a INT(10) VALUE;
  b INT(10) VALUE;
END-PR;
DCL-PR Restart;
END-PR;
DCL-PR Bump;
  n INT(10);
END-PR;

Restart();
Add(5);
Add(i * 10);
Add(arr(1) + 1);
AddTwo(100 : 200);
DSPLY ('RESULT:TOTAL=' + %CHAR(total));

// A one-argument call passing a field by reference.
Bump(total);
DSPLY ('RESULT:BUMPED=' + %CHAR(total));

// Array-element and DS-array-element assignments are unaffected.
arr(2) = 9;
arr(i + 1) = 4;
rows(2).qty = 7;
DSPLY ('RESULT:ARR=' + %CHAR(arr(2)) + ' ' + %CHAR(arr(3)) + ' ' + %CHAR(rows(2).qty));

*INLR = *ON;
RETURN;

DCL-PROC Add;
  DCL-PI *N;
    v INT(10) VALUE;
  END-PI;
  total = total + v;
END-PROC;

DCL-PROC AddTwo;
  DCL-PI *N;
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  total = total + a + b;
END-PROC;

DCL-PROC Restart;
  DCL-PI *N;
  END-PI;
  total = 0;
END-PROC;

DCL-PROC Bump;
  DCL-PI *N;
    n INT(10);
  END-PI;
  n = n + 1000;
END-PROC;
