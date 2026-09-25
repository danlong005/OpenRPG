**FREE
// An assignment's value must be of the target's type family. IBM i rejects
// a character value in a numeric field (RNF7416); %DEC or %INT converts.
DCL-S qty INT(10);
qty = '12';
DSPLY %CHAR(qty);
*INLR = *ON;
