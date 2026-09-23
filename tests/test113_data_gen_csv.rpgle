**FREE

// Test 113: DATA-GEN with %PARSER('CSV')

DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
  city VARCHAR(30);
END-DS;

DCL-S csvOut VARCHAR(500);

// Test 2: Value containing delimiter → must be quoted
DCL-DS item QUALIFIED;
  label VARCHAR(50);
  price PACKED(9:2);
END-DS;
DCL-S csvItem VARCHAR(300);
// Test 3: Suppress header row with header=no
DCL-S csvNoHdr VARCHAR(300);

// Test 1: Basic scalar DS — header + one data row
person.name = 'Alice';
person.age  = 30;
person.city = 'Boston';

DATA-GEN person %DATA(csvOut) %PARSER('CSV');
DSPLY csvOut;

item.label = 'Gadget, Pro';
item.price = 9.99;

DATA-GEN item %DATA(csvItem) %PARSER('CSV');
DSPLY csvItem;

DATA-GEN person %DATA(csvNoHdr : 'header=no') %PARSER('CSV');
DSPLY csvNoHdr;

RETURN;
