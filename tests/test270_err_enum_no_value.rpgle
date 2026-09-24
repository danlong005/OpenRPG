**FREE
// Each DCL-ENUM constant needs a value, as a DCL-C does. IBM i rejects a
// bare name (RNF3905: "Keyword CONST is missing").
DCL-ENUM sizes;
  small;
  large 16;
END-ENUM;
DSPLY %CHAR(large);
*INLR = *ON;
