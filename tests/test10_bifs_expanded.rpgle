**FREE
DCL-S text VARCHAR(100);
DCL-S pos INT(10);
DCL-S result VARCHAR(100);
DCL-S upper VARCHAR(100);
DCL-S num PACKED(9:2);
DCL-S whole INT(10);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

// %SCAN
text = 'Hello World';
pos = %SCAN('World' : text);
DSPLY %CHAR(pos);

pos = %SCAN('xyz' : text);
DSPLY %CHAR(pos);

// %SCANRPL
result = %SCANRPL('World' : 'RPG' : text);
dspLine = result;
DSPLY dspLine;

// %XLATE - lowercase to uppercase
upper = %XLATE('abcdefghijklmnopqrstuvwxyz' : 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' : text);
dspLine = upper;
DSPLY dspLine;

// %INT and %DEC
num = 42.75;
whole = %INT(num);
DSPLY %CHAR(whole);

num = %DEC(whole);
DSPLY %CHAR(num);

// %SUBST as expression
result = %SUBST(text : 1 : 5);
dspLine = result;
DSPLY dspLine;

*INLR = *ON;
