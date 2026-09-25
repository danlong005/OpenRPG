**FREE
// EVALR takes the operation extenders M and R. IBM i rejects (H), since
// EVALR right-adjusts a character value and has nothing to round (RNF5049).
DCL-S target CHAR(10);
EVALR(H) target = 'ABC';
DSPLY target;
*INLR = *ON;
