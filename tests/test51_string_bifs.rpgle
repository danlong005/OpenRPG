**FREE
// Test 51: String BIFs - %LEFT, %RIGHT, %CONCATARR, %SPLIT
DCL-S str VARCHAR(50);
DCL-S left VARCHAR(50);
DCL-S right VARCHAR(50);

// %SPLIT and %CONCATARR via procedure
DCL-S result VARCHAR(100);
DCL-S names VARCHAR(50);

str = 'Hello World';

// %LEFT - left substring
left = %LEFT(str : 5);
DSPLY left;

// %RIGHT - right substring
right = %RIGHT(str : 5);
DSPLY right;

names = 'Alice,Bob,Charlie';
result = names;
DSPLY result;

*INLR = *ON;
