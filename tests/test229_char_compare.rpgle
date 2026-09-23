**FREE
// Character comparison pads the shorter operand with blanks.
//
// RPG compares two character values of unequal length as if the shorter
// were padded on the right with blanks. rpgc compiled every comparison to a
// bare C++ ==, so `IF fld = ' '` — the standard test for a blank field —
// was false for any blank CHAR(n) with n > 1, and *BLANKS in a comparison
// named an undeclared identifier and did not compile at all.
DCL-S blank5 CHAR(5);
DCL-S ab3    CHAR(3) INZ('AB');
DCL-S vab    VARCHAR(10) INZ('AB');
DCL-S z3     CHAR(3) INZ('000');
DCL-S codes  CHAR(3) DIM(3);
DCL-S n      INT(10) INZ(5);
DCL-S p      PACKED(5:2) INZ(5);
DCL-S ptr    POINTER;

// The three ordinary ways to ask whether a field is blank.
DSPLY ('RESULT:EQSPACE=' + %CHAR(blank5 = ' '));
DSPLY ('RESULT:EQBLANKS=' + %CHAR(blank5 = *BLANKS));
DSPLY ('RESULT:EQBLANK=' + %CHAR(blank5 = *BLANK));
DSPLY ('RESULT:NEBLANKS=' + %CHAR(ab3 <> *BLANKS));

// Fixed against literal, fixed against varying, either order.
DSPLY ('RESULT:FIXLIT=' + %CHAR(ab3 = 'AB'));
DSPLY ('RESULT:LITFIX=' + %CHAR('AB' = ab3));
DSPLY ('RESULT:VARFIX=' + %CHAR(vab = ab3));
DSPLY ('RESULT:NE=' + %CHAR(ab3 <> 'AB'));

// Ordering: the padding blank takes part. 'AB' is 'AB  ' against 'AB C',
// so it is lower; against 'AB' + X'01' it is higher, since a blank sorts
// above X'01'. (X'00' would do, but a hex literal containing X'00' is
// currently truncated at the NUL — see TODO.md.)
DSPLY ('RESULT:LTLONGER=' + %CHAR('AB' < 'AB C'));
DSPLY ('RESULT:GTLOWTAIL=' + %CHAR('AB' > 'AB' + X'01'));
DSPLY ('RESULT:LE=' + %CHAR(ab3 <= 'AB'));
DSPLY ('RESULT:GE=' + %CHAR(ab3 >= 'AB'));

// Other figurative constants take the other operand's length too.
DSPLY ('RESULT:ZEROS=' + %CHAR(z3 = *ZEROS));
DSPLY ('RESULT:HIVAL=' + %CHAR(ab3 < *HIVAL));
DSPLY ('RESULT:LOVAL=' + %CHAR(ab3 > *LOVAL));
DSPLY ('RESULT:NUMZEROS=' + %CHAR(n <> *ZEROS));

// Array searches and IN compare the same way.
codes(1) = 'X';
codes(2) = 'AB';
codes(3) = 'Y';
DSPLY ('RESULT:LOOKUP=' + %CHAR(%LOOKUP('AB' : codes)));
DSPLY ('RESULT:IN=' + %CHAR(ab3 IN %LIST('ZZ' : 'AB')));

// Non-character comparisons are untouched.
DSPLY ('RESULT:NUM=' + %CHAR(n = p));
DSPLY ('RESULT:PTRNULL=' + %CHAR(ptr = *NULL));
IF ab3 = 'AB' AND blank5 = ' ';
  DSPLY 'RESULT:IF=1';
ENDIF;

*INLR = *ON;
RETURN;
