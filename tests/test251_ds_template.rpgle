**FREE
// DCL-DS header keywords in any order, and TEMPLATE.
//
// The header grammar spelled out 18 fixed keyword sequences, so TEMPLATE
// (a structure that only defines a type for LIKEDS) or a keyword order
// nobody had written out was a syntax error.
DCL-DS addr_t QUALIFIED TEMPLATE;
  street CHAR(20);
  zip    ZONED(5:0);
END-DS;

DCL-DS home LIKEDS(addr_t);
DCL-DS stops LIKEDS(addr_t) DIM(2);

// DIM before QUALIFIED, and QUALIFIED last.
DCL-DS lines DIM(3) QUALIFIED;
  qty INT(10);
END-DS;

// PSDS with a keyword on both sides of it.
DCL-DS pgm QUALIFIED PSDS;
  name CHAR(10) POS(1);
END-DS;

home.street = 'MAIN ST';
home.zip = 12345;
stops(2).zip = 99999;
lines(3).qty = 7;
DSPLY ('RESULT:HOME=' + %TRIM(home.street) + ' ' + %CHAR(home.zip));
DSPLY ('RESULT:STOPS=' + %CHAR(stops(2).zip) + ' [' + stops(1).street + ']');
DSPLY ('RESULT:LINES=' + %CHAR(lines(3).qty));
DSPLY ('RESULT:PSDS=' + %CHAR(%LEN(pgm.name)));
*INLR = *ON;
