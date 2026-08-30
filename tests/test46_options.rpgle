**FREE
DCL-PR greet VARCHAR(50);
  name VARCHAR(20) VALUE;
  title VARCHAR(10) VALUE OPTIONS(*NOPASS);
END-PR;

DSPLY greet('Alice');
DSPLY greet('Bob' : 'Mr.');

*INLR = *ON;

DCL-PROC greet;
  DCL-PI greet VARCHAR(50);
    name VARCHAR(20) VALUE;
    title VARCHAR(10) VALUE OPTIONS(*NOPASS);
  END-PI;
  IF %PARMS() >= 2;
    RETURN title + ' ' + name;
  ELSE;
    RETURN 'Hello ' + name;
  ENDIF;
END-PROC;
