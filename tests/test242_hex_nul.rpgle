**FREE
// Hex literals keep every byte, X'00' included.
//
// A hex literal travelled from the lexer as a C string, so a 00 byte ended
// it: X'C1004142' was just 'A', and *ALLX'00' was an empty pattern that
// rpg_all looped on forever. Separately, bytes were emitted into the
// generated C++ as \xNN, a greedy escape, so a control byte followed by a
// hex-digit character (X'0A' then 'B') merged into one wrong byte.
DCL-S s VARCHAR(20);
DCL-S f CHAR(4);
DCL-S q CHAR(6);

// A NUL in the middle and at the start: every byte is kept.
s = 'A' + X'00' + 'B';
DSPLY ('RESULT:MID=' + %CHAR(%LEN(s)) + ' ' + %CHAR(%SCAN('B' : s)));
s = X'C1004142';
DSPLY ('RESULT:LEAD=' + %CHAR(%LEN(s)) + ' ' + %SUBST(s : 3 : 2));
s = X'00' + 'Z';
DSPLY ('RESULT:FIRST=' + %CHAR(%LEN(s)) + ' ' + %SUBST(s : 2 : 1));

// *ALLX'00' fills the field with NULs: *LOVAL, not blanks.
f = *ALLX'00';
DSPLY ('RESULT:ALLNUL=' + %CHAR(%LEN(f)) + ' ' + %CHAR(f = *LOVAL) + %CHAR(f = *BLANKS));

// A control byte before a hex-digit character stays two bytes.
s = X'0A' + 'B';
DSPLY ('RESULT:GREEDY=' + %CHAR(%LEN(s)) + ' ' + %SUBST(s : 2 : 1));

// A *ALL pattern holding a quote or a backslash is emitted escaped.
q = *ALL'a"\';
DSPLY ('RESULT:ALLQ=' + q);

*INLR = *ON;
