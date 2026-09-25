**FREE

// Test 99: DATA-INTO — parse JSON into data structure

DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age INT(10);
  city VARCHAR(30);
END-DS;

DCL-S jsonData VARCHAR(500);

// Test 2: Numeric types
DCL-DS product QUALIFIED;
  id INT(10);
  price PACKED(9:2);
  qty INT(10);
  label VARCHAR(30);
END-DS;
DCL-S jsonProduct VARCHAR(300);
// Test 3: Missing fields default to zero/empty
DCL-DS partial QUALIFIED;
  x INT(10);
  y INT(10);
  note VARCHAR(20);
END-DS;
DCL-S jsonPartial VARCHAR(200);

// Test 1: Basic DATA-INTO with case=any
jsonData = '{"name":"Alice","age":30,"city":"Boston"}';

DATA-INTO person %DATA(jsonData : 'doc=string case=any') %PARSER('JSON');

DSPLY ('Name: ' + person.name);
DSPLY ('Age: ' + %CHAR(person.age));
DSPLY ('City: ' + person.city);

jsonProduct = '{"id":42,"price":19.99,"qty":100,"label":"Widget"}';

DATA-INTO product %DATA(jsonProduct : 'case=any') %PARSER('JSON');

DSPLY ('ID: ' + %CHAR(product.id));
DSPLY ('Price: ' + %CHAR(product.price));
DSPLY ('Qty: ' + %CHAR(product.qty));
DSPLY ('Label: ' + product.label);

jsonPartial = '{"x":7}';

DATA-INTO partial %DATA(jsonPartial : 'case=any') %PARSER('JSON');

DSPLY ('X: ' + %CHAR(partial.x));
DSPLY ('Y: ' + %CHAR(partial.y));
DSPLY ('Note: [' + partial.note + ']');

RETURN;
