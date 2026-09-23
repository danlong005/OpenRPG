**FREE

// Test 85: %GETENV built-in function
// Reads environment variables

DCL-S homePath  VARCHAR(256);
DCL-S userName  VARCHAR(50);
DCL-S missing   VARCHAR(50);
DCL-S dbUrl     VARCHAR(256);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

// Read standard environment variables
homePath = %GETENV('HOME');
dspLine = homePath;
DSPLY dspLine;

userName = %GETENV('USER');
DSPLY userName;

// Reading a non-existent variable returns empty string
missing = %GETENV('DOES_NOT_EXIST_XYZ');
IF missing = '';
  DSPLY 'Variable not set';
ENDIF;

// Use in expression
IF %GETENV('HOME') <> '';
  DSPLY 'HOME is set';
ENDIF;

// Typical use case: database connection string from environment
dbUrl = %GETENV('DATABASE_URL');
IF dbUrl <> '';
  dspLine = dbUrl;
  DSPLY dspLine;
ELSE;
  DSPLY 'No DATABASE_URL configured';
ENDIF;

*INLR = *ON;
RETURN;
