**FREE

// Test 89: XML-INTO — PATH option + nested DS

// Test 1: PATH option to navigate into XML
DCL-DS order QUALIFIED;
  id INT(10);
  product VARCHAR(40);
  qty INT(10);
END-DS;

DCL-S xmlData VARCHAR(500);
// Test 2: Nested DS with LIKEDS subfield
DCL-DS address QUALIFIED;
  street VARCHAR(50);
  city VARCHAR(30);
  state CHAR(2);
END-DS;
DCL-DS customer QUALIFIED;
  name VARCHAR(50);
  age INT(10);
  addr LIKEDS(address);
END-DS;
DCL-S xmlCust VARCHAR(500);
// Test 3: Combined PATH + nested DS
DCL-DS location QUALIFIED;
  name VARCHAR(40);
  lat PACKED(9:4);
  lon PACKED(9:4);
END-DS;
DCL-DS site QUALIFIED;
  id INT(10);
  label VARCHAR(40);
  loc LIKEDS(location);
END-DS;
DCL-S xmlSite VARCHAR(500);

xmlData = '<response><status>ok</status><data><orders><order><id>5001</id><product>Laptop</product><qty>2</qty></order></orders></data></response>';

XML-INTO order %XML(xmlData : 'case=any path=response/data/orders/order');

DSPLY 'Order: ' + %CHAR(order.id) + ' ' + order.product +
      ' qty=' + %CHAR(order.qty);

xmlCust = '<customer><name>Alice</name><age>30</age><addr><street>123 Main St</street><city>Boston</city><state>MA</state></addr></customer>';

XML-INTO customer %XML(xmlCust : 'case=any');

DSPLY 'Name: ' + customer.name;
DSPLY 'Age: ' + %CHAR(customer.age);
DSPLY 'Street: ' + customer.addr.street;
DSPLY 'City: ' + customer.addr.city;
DSPLY 'State: ' + customer.addr.state;

xmlSite = '<root><sites><site><id>42</id><label>HQ</label><loc><name>Headquarters</name><lat>42.3601</lat><lon>-71.0589</lon></loc></site></sites></root>';

XML-INTO site %XML(xmlSite : 'case=any path=root/sites/site');

DSPLY 'Site: ' + %CHAR(site.id) + ' ' + site.label;
DSPLY 'Loc: ' + site.loc.name;
DSPLY 'Lat: ' + %CHAR(site.loc.lat);
DSPLY 'Lon: ' + %CHAR(site.loc.lon);

RETURN;
