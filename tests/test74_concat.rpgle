**FREE
DCL-S result VARCHAR(100);
DCL-S name VARCHAR(20);
DCL-S city VARCHAR(20);
DCL-S state VARCHAR(2);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

name = 'Alice';
city = 'Dallas';
state = 'TX';

// Basic concat with comma separator
result = %CONCAT(', ': name: city: state);
dspLine = result;  // Alice, Dallas, TX
DSPLY dspLine;

// Concat with dash separator
result = %CONCAT('-': '2024': '03': '15');
dspLine = result;  // 2024-03-15
DSPLY dspLine;

// Concat two items
result = %CONCAT(' ': 'Hello': 'World');
dspLine = result;  // Hello World
DSPLY dspLine;

// Concat with empty separator
result = %CONCAT('': 'A': 'B': 'C');
dspLine = result;  // ABC
DSPLY dspLine;

*INLR = *ON;
