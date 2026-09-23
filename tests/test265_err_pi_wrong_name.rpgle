**FREE
// A procedure interface's name must be the procedure's own name, or *N.
DCL-S total INT(10);
total = add(2 : 3);
DSPLY %CHAR(total);
*INLR = *ON;

DCL-PROC add;
  DCL-PI sum INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;
