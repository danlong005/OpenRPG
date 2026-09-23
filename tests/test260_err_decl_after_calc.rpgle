**FREE
// Declarations come before executable code: a DCL-S after a calculation in
// the main procedure is out of sequence on IBM i (RNF0724).
DCL-S a INT(10);
a = 1;
DCL-S b INT(10);
b = a + 1;
*INLR = *ON;
