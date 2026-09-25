**FREE
// *USER is only an initial value, INZ(*USER). IBM i rejects it on the right
// of an assignment (RNF7416).
DCL-S who CHAR(10);
who = *USER;
DSPLY who;
*INLR = *ON;
