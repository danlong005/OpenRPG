**FREE
// DATA-INTO names its parser. IBM i rejects it without %PARSER as the
// third operand (RNF5449: "The third operand of DATA-INTO must be %PARSER").
DCL-DS person QUALIFIED;
  name VARCHAR(20);
END-DS;
DCL-S json VARCHAR(100) INZ('{"name":"Ann"}');
DATA-INTO person %DATA(json : 'case=any');
DSPLY person.name;
*INLR = *ON;
