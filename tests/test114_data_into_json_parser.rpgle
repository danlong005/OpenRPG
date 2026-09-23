**FREE

// Test 114: DATA-INTO / DATA-GEN with explicit %PARSER('JSON')
// Behavior must be identical to omitting %PARSER entirely.

DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
  city VARCHAR(30);
END-DS;

DCL-S jsonIn  VARCHAR(500);
DCL-S jsonOut VARCHAR(500);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

jsonIn = '{"name":"Diana","age":28,"city":"Austin"}';

DATA-INTO person %DATA(jsonIn : 'case=any') %PARSER('JSON');

DSPLY ('Name: ' + person.name);
DSPLY ('Age: '  + %CHAR(person.age));
DSPLY ('City: ' + person.city);

person.name = 'Eve';
person.age  = 35;
person.city = 'Denver';

DATA-GEN person %DATA(jsonOut) %PARSER('JSON');

dspLine = jsonOut;
DSPLY dspLine;

RETURN;
