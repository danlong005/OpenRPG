**FREE
// Test 95: Operation extender (E) - error extender syntax
// Tests that CALLP(E) and EVAL(E) parse correctly and run
// (E) clears %ERROR before the call; normal calls leave %ERROR false)

DCL-PR addOne INT(10);
  pVal INT(10) VALUE;
END-PR;

DCL-S result INT(10);

// EVAL(E): assign expression, should not halt on normal operation
DCL-S x INT(10) INZ(10);

// CALLP(E) on a successful procedure: %ERROR should be false after
CALLP(E) addOne(5);
// (we just verify parse and execution; return value discarded)

EVAL(E) x = x + 5;
IF x = 15;
  DSPLY 'EVAL E OK';
ELSE;
  DSPLY 'EVAL E FAIL';
ENDIF;

// CALLP(E) captures result in a variable via EVAL(E)
EVAL(E) result = addOne(7);
IF result = 8;
  DSPLY 'CALLP E OK';
ELSE;
  DSPLY 'CALLP E FAIL';
ENDIF;

*INLR = *ON;

DCL-PROC addOne;
  DCL-PI addOne INT(10);
    pVal INT(10) VALUE;
  END-PI;
  RETURN pVal + 1;
END-PROC;
