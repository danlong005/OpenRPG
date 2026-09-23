**FREE
// A procedure with no parameters and no return value may omit its
// DCL-PI entirely; it was a syntax error, because every DCL-PROC form in
// the grammar required one.
DCL-S count INT(10) INZ(0);

DCL-PR Tick;
END-PR;
DCL-PR Report;
END-PR;
DCL-PR Guarded;
END-PR;

Tick();
Tick();
CALLP Report();
NoProto();
Guarded();
DSPLY ('RESULT:COUNT=' + %CHAR(count));
*INLR = *ON;
RETURN;

// No DCL-PI: uses a module global.
DCL-PROC Tick;
  count = count + 1;
END-PROC;

// No DCL-PI, with a local of its own.
DCL-PROC Report;
  DCL-S msg VARCHAR(20);
  msg = 'ticks ' + %CHAR(count);
  DSPLY ('RESULT:REPORT=' + %TRIM(%SUBST(msg : 1 : 5)) + %CHAR(count));
END-PROC;

// No DCL-PI and no prototype either.
DCL-PROC NoProto;
  count = count + 10;
END-PROC;

// No DCL-PI, with ON-EXIT.
DCL-PROC Guarded EXPORT;
  count = count + 100;
ON-EXIT;
  DSPLY 'RESULT:ONEXIT=ran';
END-PROC;
