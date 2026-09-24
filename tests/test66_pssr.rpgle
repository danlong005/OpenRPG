**FREE
DCL-S result INT(10);
DCL-S errMsg VARCHAR(50);

result = 10;
DSPLY %CHAR(result);
*INLR = *ON;

BEGSR *PSSR;
  errMsg = 'Error caught by *PSSR';
  DSPLY errMsg;
ENDSR;
