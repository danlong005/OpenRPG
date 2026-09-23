**FREE
// NOT binds tighter than a comparison, so `NOT x = 0` is (NOT x) = 0, and
// NOT on a number is an error on IBM i (RNF7421). NOT (x = 0) is the way to
// negate the comparison.
DCL-S x INT(10) INZ(5);
IF NOT x = 0;
  DSPLY 'not zero';
ENDIF;
*INLR = *ON;
