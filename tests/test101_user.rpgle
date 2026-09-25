**FREE

// Test 101: *USER figurative constant
// *USER is an initial value only, INZ(*USER): the current user profile,
// CHAR(10). IBM i rejects it in an expression (RNF7416); test 285 is that.

DCL-S currentUser CHAR(10) INZ(*USER);
DCL-S msg         VARCHAR(50);

// Verify it's non-empty
IF currentUser <> '';
  DSPLY 'User is set';
ELSE;
  DSPLY 'User is empty';
ENDIF;

// The field holding it concatenates like any other (value is env-specific)
msg = 'Hello ' + %TRIM(currentUser);
IF %LEN(%TRIMR(msg)) > 0;
  DSPLY 'Greeting ok';
ENDIF;

RETURN;
