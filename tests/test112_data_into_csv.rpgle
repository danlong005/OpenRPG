**FREE

// Test 112: DATA-INTO with %PARSER('CSV')

DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
  city VARCHAR(30);
END-DS;

DCL-S csvStr VARCHAR(500);

// Test 2: Array DS — multiple rows
DCL-DS emp DIM(*VAR:10) QUALIFIED;
  name VARCHAR(40);
  dept VARCHAR(20);
END-DS;
DCL-S csvEmp VARCHAR(500);
// Test 3: Missing fields default to zero/empty
DCL-DS partial QUALIFIED;
  x INT(10);
  y INT(10);
  note VARCHAR(20);
END-DS;
DCL-S csvPartial VARCHAR(200);

// Test 1: Basic scalar DS
csvStr = 'NAME,AGE,CITY' + X'0A' + 'Alice,30,Boston';

DATA-INTO person %DATA(csvStr : 'case=any') %PARSER('CSV');

DSPLY 'Name: ' + person.name;
DSPLY 'Age: '  + %CHAR(person.age);
DSPLY 'City: ' + person.city;

csvEmp = 'NAME,DEPT' + X'0A' + 'Bob,Engineering' + X'0A' + 'Carol,Marketing';

DATA-INTO emp %DATA(csvEmp : 'case=any') %PARSER('CSV');

DSPLY 'Count: ' + %CHAR(%ELEM(emp));
DSPLY emp(1).name + ' / ' + emp(1).dept;
DSPLY emp(2).name + ' / ' + emp(2).dept;

csvPartial = 'X' + X'0A' + '7';

DATA-INTO partial %DATA(csvPartial : 'case=any') %PARSER('CSV');

DSPLY 'X: ' + %CHAR(partial.x);
DSPLY 'Y: ' + %CHAR(partial.y);
DSPLY 'Note: [' + partial.note + ']';

RETURN;
