**FREE
// Test 95: Operation extender (E) on CALLP
// CALLP(E) traps an error in the call: %ERROR is set and %STATUS holds the
// status, and the program carries on. EVAL takes no (E) on IBM i (RNF5049);
// test 278 is that form.

DCL-PR addOne INT(10);
  pVal INT(10) VALUE;
END-PR;
DCL-PR divide INT(10);
  num INT(10) VALUE;
  den INT(10) VALUE;
END-PR;

// A call that succeeds leaves %ERROR off
CALLP(E) addOne(5);
IF NOT %ERROR;
  DSPLY 'CALLP E OK';
ELSE;
  DSPLY 'CALLP E FAIL';
ENDIF;

// A call that fails is trapped. The division by zero (102) happens inside
// the procedure, so the caller sees 202, "called procedure failed".
CALLP(E) divide(1 : 0);
IF %ERROR;
  DSPLY ('CALLP E caught ' + %CHAR(%STATUS));
ELSE;
  DSPLY 'CALLP E missed';
ENDIF;

*INLR = *ON;

DCL-PROC addOne;
  DCL-PI addOne INT(10);
    pVal INT(10) VALUE;
  END-PI;
  RETURN pVal + 1;
END-PROC;

DCL-PROC divide;
  DCL-PI divide INT(10);
    num INT(10) VALUE;
    den INT(10) VALUE;
  END-PI;
  RETURN num / den;
END-PROC;
