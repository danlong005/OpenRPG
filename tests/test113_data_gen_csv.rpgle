**FREE

// Test 113: DATA-GEN with %GEN('CSV')

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
// Test 3: Suppress the header row: header=no, an option of the CSV generator
DCL-S csvNoHdr VARCHAR(300);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

// Test 1: Basic scalar DS — header + one data row
person.name = 'Alice';
person.age  = 30;
person.city = 'Boston';

DATA-GEN person %DATA(csvOut) %GEN('CSV');
dspLine = csvOut;
DSPLY dspLine;

item.label = 'Gadget, Pro';
item.price = 9.99;

DATA-GEN item %DATA(csvItem) %GEN('CSV');
dspLine = csvItem;
DSPLY dspLine;

DATA-GEN person %DATA(csvNoHdr) %GEN('CSV' : 'header=no');
dspLine = csvNoHdr;
DSPLY dspLine;

RETURN;
