**FREE

// Test 100: DATA-GEN — generate JSON from data structure

DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age INT(10);
  city VARCHAR(30);
END-DS;

DCL-S jsonOut VARCHAR(500);

// Test 2: Numeric fields
DCL-DS item QUALIFIED;
  id INT(10);
  price PACKED(9:2);
  active INT(10);
END-DS;
DCL-S jsonItem VARCHAR(300);
// Test 3: Special characters in strings
DCL-DS msg QUALIFIED;
  text VARCHAR(100);
  code INT(10);
END-DS;
DCL-S jsonMsg VARCHAR(500);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

person.name = 'Bob';
person.age = 25;
person.city = 'Seattle';

DATA-GEN person %DATA(jsonOut : 'doc=string') %GEN('JSON');

dspLine = jsonOut;
DSPLY dspLine;

item.id = 99;
item.price = 4.50;
item.active = 1;

DATA-GEN item %DATA(jsonItem) %GEN('JSON');

dspLine = jsonItem;
DSPLY dspLine;

msg.text = 'Hello "world"';
msg.code = 42;

DATA-GEN msg %DATA(jsonMsg) %GEN('JSON');

dspLine = jsonMsg;
DSPLY dspLine;

RETURN;
