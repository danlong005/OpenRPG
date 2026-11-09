**FREE
DCL-S n INT(10) INZ(0);
DCL-S total INT(10) INZ(0);
DCL-PR addIt INT(10);
  x INT(10) VALUE;
END-PR;

n = 1;
total = 0;
DOW n <= 2;
  n += 1;
ENDDO;
IF n = 3;
  total = addIt(n);
ELSE;
  total = -1;
ENDIF;
EXSR show;
*INLR = *ON;

BEGSR show;
  DSPLY ('TOTAL=' + %CHAR(total));
ENDSR;

DCL-PROC addIt;
  DCL-PI *N INT(10);
    x INT(10) VALUE;
  END-PI;
  RETURN x * 10;
END-PROC;
