**FREE

// Test 87: XML-INTO — parse XML into data structure

DCL-DS order QUALIFIED;
  id INT(10);
  customer VARCHAR(50);
  item VARCHAR(30);
  qty INT(10);
  price PACKED(9:2);
END-DS;

DCL-S xmlData VARCHAR(500);

// Test 2: XML with case-insensitive matching
DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age INT(10);
  city VARCHAR(30);
END-DS;
DCL-S xmlPerson VARCHAR(300);
// Test 3: XML without options (defaults)
DCL-DS config QUALIFIED;
  host VARCHAR(50);
  port INT(10);
  debug VARCHAR(10);
END-DS;
DCL-S xmlConfig VARCHAR(300);
// Test 4: XML with missing elements (should default to zero/empty)
DCL-DS partial QUALIFIED;
  x INT(10);
  y INT(10);
  label VARCHAR(20);
END-DS;
DCL-S xmlPartial VARCHAR(200);
// Test 5: XML with special characters (entities)
DCL-DS msg QUALIFIED;
  text VARCHAR(100);
  sender VARCHAR(50);
END-DS;
DCL-S xmlMsg VARCHAR(300);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

// Test 1: Basic XML-INTO with case=any
xmlData = '<order><ID>1001</ID><Customer>Acme Corp</Customer><Item>Widget</Item><QTY>25</QTY><Price>19.99</Price></order>';

XML-INTO order %XML(xmlData : 'case=any');

DSPLY ('Order: ' + %CHAR(order.id));
dspLine = ('Customer: ' + order.customer);
DSPLY dspLine;
DSPLY ('Item: ' + order.item);
DSPLY ('Qty: ' + %CHAR(order.qty));
DSPLY ('Price: ' + %CHAR(order.price));

xmlPerson = '<person><Name>Alice</Name><Age>30</Age><City>Boston</City></person>';

XML-INTO person %XML(xmlPerson : 'case=any');

DSPLY ('Name: ' + person.name);
DSPLY ('Age: ' + %CHAR(person.age));
DSPLY ('City: ' + person.city);

xmlConfig = '<config><HOST>localhost</HOST><PORT>8080</PORT><DEBUG>true</DEBUG></config>';

XML-INTO config %XML(xmlConfig);

dspLine = ('Host: ' + config.host);
DSPLY dspLine;
DSPLY ('Port: ' + %CHAR(config.port));
DSPLY ('Debug: ' + config.debug);

xmlPartial = '<point><X>42</X></point>';

XML-INTO partial %XML(xmlPartial);

DSPLY ('X: ' + %CHAR(partial.x));
DSPLY ('Y: ' + %CHAR(partial.y));
DSPLY ('Label: [' + partial.label + ']');

xmlMsg = '<message><text>Price &lt; $10 &amp; tax</text><sender>Smith</sender></message>';

XML-INTO msg %XML(xmlMsg : 'case=any');

dspLine = ('Text: ' + msg.text);
DSPLY dspLine;
dspLine = ('Sender: ' + msg.sender);
DSPLY dspLine;

RETURN;
