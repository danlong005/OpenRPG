**FREE
DCL-S statusCode INT(10);
DCL-S errFlag IND;

// %STATUS returns last error status (0 = no error)
statusCode = %STATUS();
DSPLY %CHAR(statusCode);

// %ERROR is an indicator: whether the last operation had an error
errFlag = %ERROR();
DSPLY %CHAR(errFlag);

// Normal operation - status stays 0
statusCode = 42;
statusCode = %STATUS();
DSPLY %CHAR(statusCode);

*INLR = *ON;
