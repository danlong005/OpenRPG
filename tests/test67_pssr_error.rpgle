**FREE
DCL-S errMsg VARCHAR(50);
DCL-S myDate DATE;
DCL-S badDate DATE;
DCL-S diff INT(10);

DSPLY 'Before error';
myDate = %DATE('2024-01-15');
badDate = %DATE('not-a-date');
diff = %DIFF(badDate:myDate:*DAYS);
DSPLY 'After error';
*INLR = *ON;

BEGSR *PSSR;
  errMsg = 'Error caught by *PSSR';
  DSPLY errMsg;
ENDSR;
