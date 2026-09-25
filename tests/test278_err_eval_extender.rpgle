**FREE
// EVAL takes the operation extenders H, M and R. IBM i rejects the others,
// including (E), which is for CALLP and file operations (RNF5049).
DCL-S x INT(10) INZ(10);
EVAL(E) x = x + 5;
DSPLY %CHAR(x);
*INLR = *ON;
