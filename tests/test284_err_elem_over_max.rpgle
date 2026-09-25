**FREE
// A varying array holds at most the maximum in its DIM. IBM i rejects
// setting %ELEM, or %ELEM(... : *ALLOC), to a constant above it (RNF7563).
DCL-S nums INT(10) DIM(*VAR:10);
%ELEM(nums : *ALLOC) = 50;
DSPLY %CHAR(%ELEM(nums : *ALLOC));
*INLR = *ON;
