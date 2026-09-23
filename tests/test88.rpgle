**FREE

// Test 88: XML-INTO — Array DS targets

// Test 1: Fixed DIM array DS
DCL-DS item QUALIFIED DIM(5);
  name VARCHAR(50);
  qty INT(10);
  price PACKED(9:2);
END-DS;

DCL-S xmlItems VARCHAR(500);
// Test 2: DIM(*VAR) array DS
DCL-DS emp QUALIFIED DIM(*VAR:10);
  id INT(10);
  name VARCHAR(40);
END-DS;
DCL-S xmlEmps VARCHAR(500);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

xmlItems = '<items><item><name>Widget</name><qty>5</qty><price>19.99</price></item><item><name>Gadget</name><qty>3</qty><price>29.50</price></item><item><name>Gizmo</name><qty>10</qty><price>9.95</price></item></items>';

XML-INTO item %XML(xmlItems : 'case=any path=items');

dspLine = ('Item 1: ' + item(1).name + ' qty=' + %CHAR(item(1).qty) +
      ' price=' + %CHAR(item(1).price));
DSPLY dspLine;
dspLine = ('Item 2: ' + item(2).name + ' qty=' + %CHAR(item(2).qty) +
      ' price=' + %CHAR(item(2).price));
DSPLY dspLine;
dspLine = ('Item 3: ' + item(3).name + ' qty=' + %CHAR(item(3).qty) +
      ' price=' + %CHAR(item(3).price));
DSPLY dspLine;

xmlEmps = '<employees><emp><id>101</id><name>Alice</name></emp><emp><id>102</id><name>Bob</name></emp></employees>';

XML-INTO emp %XML(xmlEmps : 'case=any path=employees');

DSPLY ('Emp count: ' + %CHAR(%ELEM(emp)));
dspLine = ('Emp 1: ' + %CHAR(emp(1).id) + ' ' + emp(1).name);
DSPLY dspLine;
dspLine = ('Emp 2: ' + %CHAR(emp(2).id) + ' ' + emp(2).name);
DSPLY dspLine;

RETURN;
