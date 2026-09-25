**FREE
// A copy member is fixed-format unless its own first line is **FREE,
// whatever the including source is. IBM i reads this member's position-1
// code as out of sequence (RNF0257).
/COPY tests/copybook300_fixed.rpgle
DSPLY %CHAR(fromCopy);
*INLR = *ON;
