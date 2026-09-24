**FREE
// Subroutines come after all other calculations in a procedure. IBM i
// ignores a calculation after an ENDSR (RNF5005), in the main procedure
// and in a subprocedure alike.
DCL-S n INT(10);

BEGSR bump;
  n = n + 1;
ENDSR;

EXSR bump;
DSPLY %CHAR(n);
*INLR = *ON;
