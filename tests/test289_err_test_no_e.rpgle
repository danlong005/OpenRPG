**FREE
// In free form TEST needs the E extender: IBM i rejects it without one
// (RNF5056), since there is no error indicator to set instead.
DCL-S d DATE;
TEST d;
DSPLY 'done';
*INLR = *ON;
