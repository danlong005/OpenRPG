**FREE
// Every scalar type is accepted as a data-structure subfield.
//
// The subfield grammar spelled out INT, CHAR, VARCHAR and PACKED only,
// each with a fixed set of keywords, so a ZONED, IND, DATE, UNS or FLOAT
// subfield — ordinary in real record layouts — was a syntax error, as was
// a keyword combination nobody had spelled out (DIM with POS, say).
DCL-DS rec QUALIFIED;
  qty    ZONED(7:2);
  active IND;
  due    DATE;
  seen   TIME;
  stamp  TIMESTAMP;
  units  UNS(10);
  rate   FLOAT(8);
  ptr    POINTER;
  code   CHAR(4);
  DCL-SUBF amt ZONED(5:1);
END-DS;

DCL-DS lay QUALIFIED;
  whole  CHAR(10);
  part   CHAR(3) OVERLAY(whole : 4);
  nums   ZONED(3:0) DIM(2) POS(20);
END-DS;

// Each starts at its type's initial value.
DSPLY ('RESULT:INIT=' + %CHAR(rec.qty) + ' ' + %CHAR(rec.active) + ' ' +
       %CHAR(rec.units) + ' [' + rec.code + ']');
DSPLY ('RESULT:NULLPTR=' + %CHAR(rec.ptr = *NULL));

// And each holds its declared shape: ZONED keeps and truncates its scale.
rec.qty = 12.345;
rec.amt = 99.99;
rec.active = *ON;
rec.units = 42;
rec.rate = 0.5;
rec.due = %DATE('2026-09-22');
DSPLY ('RESULT:SET=' + %CHAR(rec.qty) + ' ' + %CHAR(rec.amt) + ' ' +
       %CHAR(rec.active) + ' ' + %CHAR(rec.units) + ' ' + %CHAR(rec.due));

// Keyword combinations no alternative used to spell.
lay.whole = 'ABCDEFGHIJ';
lay.nums(2) = 7;
DSPLY ('RESULT:LAYOUT=' + lay.part + ' ' + %CHAR(lay.nums(2)) + ' ' + %CHAR(lay.nums(1)));

*INLR = *ON;
