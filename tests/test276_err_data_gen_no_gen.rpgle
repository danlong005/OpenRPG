**FREE
// DATA-GEN names its generator. IBM i rejects it without %GEN as the third
// operand (RNF5454: "The third operand of DATA-GEN must be %GEN"), and
// %PARSER in that place is rejected the same way.
DCL-DS person QUALIFIED;
  name VARCHAR(20) INZ('Ann');
END-DS;
DCL-S json VARCHAR(50);
DATA-GEN person %DATA(json) %PARSER('JSON');
DSPLY json;
*INLR = *ON;
