**FREE
// A character initial value longer than its field is an error on IBM i
// (RNF3431); it is not truncated.
DCL-S c CHAR(5) INZ('ABCDEFG');
DSPLY c;
*INLR = *ON;
