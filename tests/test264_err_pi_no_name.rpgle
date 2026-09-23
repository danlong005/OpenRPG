**FREE
// A procedure interface must be named: the procedure's own name, or *N.
// With no name, IBM i reads the return type INT(10) as the name.
DCL-S total INT(10);
total = add(2 : 3);
DSPLY %CHAR(total);
*INLR = *ON;

DCL-PROC add;
  DCL-PI INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;
