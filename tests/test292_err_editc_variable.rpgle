**FREE
// The edit code of %EDITC is fixed when the program is compiled: a literal
// or a named constant. A variable is rejected (IBM: RNF0355).
DCL-S amt PACKED(7:2) INZ(12.5);
DCL-S code CHAR(1) INZ('1');
DCL-S line VARCHAR(52);
line = %EDITC(amt : code);
DSPLY line;
*INLR = *ON;
