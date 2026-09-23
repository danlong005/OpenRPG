**FREE
// Test 94: Operation extenders (H), (R), (P), (N) and EVALR(H)
DCL-S a PACKED(7:1) INZ(7.0);
DCL-S b PACKED(7:0) INZ(2);
DCL-S result INT(10);

// (R): same rounding semantics as (H)
DCL-S result2 INT(10);
// (MH): multiple extenders including H
DCL-S result3 INT(10);
// (P): pad extender — no-op, verify parse and basic assignment
DCL-S padStr CHAR(10) INZ('          ');
// (N): no-lock extender — no-op outside file ops, verify parse
DCL-S nval INT(10) INZ(1);
// EVALR(H): round numeric, then right-adjust into char field
DCL-S rTarget CHAR(10) INZ('          ');
DCL-S rNum PACKED(7:1) INZ(3.7);

// (H): half-adjust rounds 3.5 to 4
EVAL(H) result = a / b;
IF result = 4;
  DSPLY 'EXTENDER H OK';
ELSE;
  DSPLY 'EXTENDER H FAIL';
ENDIF;

EVAL(R) result2 = a / b;
IF result2 = 4;
  DSPLY 'EXTENDER R OK';
ELSE;
  DSPLY 'EXTENDER R FAIL';
ENDIF;

EVAL(MH) result3 = a / b;
IF result3 = 4;
  DSPLY 'COMBO MH OK';
ELSE;
  DSPLY 'COMBO MH FAIL';
ENDIF;

EVAL(P) padStr = 'HELLO';
IF %TRIM(padStr) = 'HELLO';
  DSPLY 'EXTENDER P OK';
ELSE;
  DSPLY 'EXTENDER P FAIL';
ENDIF;

EVAL(N) nval = nval + 1;
IF nval = 2;
  DSPLY 'EXTENDER N OK';
ELSE;
  DSPLY 'EXTENDER N FAIL';
ENDIF;

EVALR(H) rTarget = rNum;
// round(3.7)=4, right-adjusted in 10 chars -> last char is '4'
IF %SUBST(rTarget:10:1) = '4';
  DSPLY 'EVALR H OK';
ELSE;
  DSPLY 'EVALR H FAIL';
ENDIF;

*INLR = *ON;
