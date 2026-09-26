**FREE
// DS subfields keep their declared attributes.
//
// Codegen looked up a field's type, length and scale by bare name only, so
// anything reached through a data structure lost its declaration. A
// CHAR(n) subfield started as an empty string instead of n blanks, and a
// PACKED(9:2) subfield printed through %CHAR as 1250.000000 where the same
// value in a standalone field prints 1250.00.
DCL-DS addr QUALIFIED INZ;
  zip  CHAR(5);
  lat  PACKED(9:4);
END-DS;

DCL-DS cust QUALIFIED INZ;
  name  CHAR(6);
  codes CHAR(2) DIM(3);
  bal   PACKED(9:2);
  home  LIKEDS(addr);
END-DS;

DCL-DS line QUALIFIED INZ DIM(2);
  sku   CHAR(4);
  price PACKED(7:2);
END-DS;

// A CHAR subfield starts as blanks — in a plain DS, in each element of a
// DS array, in each element of a DIM'd subfield, and in a nested LIKEDS.
DSPLY ('RESULT:NAME=[' + cust.name + '] ' + %CHAR(%LEN(cust.name)));
DSPLY ('RESULT:SKU2=[' + line(2).sku + ']');
DSPLY ('RESULT:CODE3=[' + cust.codes(3) + ']');
DSPLY ('RESULT:ZIP=[' + cust.home.zip + ']');

// %CHAR formats a numeric subfield at its own scale, however it is reached.
// (The nested one is read at its initial zero: a.b.c is not yet accepted
// as an assignment target — see TODO.md.)
cust.bal = 1250;
line(2).price = 87.4;
DSPLY ('RESULT:BAL=' + %CHAR(cust.bal));
DSPLY ('RESULT:PRICE2=' + %CHAR(line(2).price));
DSPLY ('RESULT:LAT=' + %CHAR(cust.home.lat));
DSPLY ('RESULT:ZEROBAL=' + %CHAR(line(1).price));

// EVAL(H) rounds at the subfield's scale, not at the units position.
EVAL(H) cust.bal = 10.555;
DSPLY ('RESULT:HALF=' + %CHAR(cust.bal));

// Figurative constants assigned to a subfield take its type and length.
cust.name = 'ABC';
cust.name = *BLANKS;
DSPLY ('RESULT:BLANKS=[' + cust.name + '] ' + %CHAR(%LEN(cust.name)));
cust.name = *ALL'x';
DSPLY ('RESULT:ALLX=[' + cust.name + ']');

// %SIZE sees the declaration too.
DSPLY ('RESULT:SIZE=' + %CHAR(%SIZE(cust.name)) + '/' + %CHAR(%SIZE(cust.bal)));

*INLR = *ON;
RETURN;
