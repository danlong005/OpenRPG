**FREE
// A nested subfield is an assignment target, not only an expression.
//
// ord.ship.city was readable, but assigning to it was a syntax error: the
// target grammar accepted only one level of qualification.
DCL-DS addr_t QUALIFIED TEMPLATE;
  city  CHAR(8);
  zip   ZONED(5:0);
  tags  CHAR(2) DIM(3);
END-DS;

DCL-DS ord QUALIFIED;
  id    INT(10);
  ship  LIKEDS(addr_t);
END-DS;

DCL-DS hist QUALIFIED DIM(2);
  ship  LIKEDS(addr_t);
END-DS;

ord.ship.city = 'SPRINGFIELD';
ord.ship.zip = 12345.9;
ord.ship.tags(2) = 'XY';
hist(2).ship.city = 'OMAHA';
DSPLY ('RESULT:NESTED=[' + ord.ship.city + '] ' + %CHAR(ord.ship.zip));
DSPLY ('RESULT:DIMSUB=' + ord.ship.tags(2));
DSPLY ('RESULT:ARRAYELT=' + %TRIM(hist(2).ship.city) + ' [' + hist(1).ship.city + ']');
*INLR = *ON;
