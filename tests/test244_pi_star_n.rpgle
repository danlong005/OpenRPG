**FREE
// DCL-PI *N — the standard, IBM-recommended way to write a procedure
// interface — was a syntax error: *N was not a token at all. It is a name
// only as the first token after DCL-PI; anywhere else "*N" is still
// multiplication by N, which this test also checks.
DCL-S n     INT(10) INZ(6);
DCL-S total INT(10) INZ(7);

DCL-PR Twice INT(10);
  v INT(10) VALUE;
END-PR;
DCL-PR Greet VARCHAR(20);
  who VARCHAR(10) VALUE;
END-PR;
DCL-PR Note;
END-PR;
DCL-PR Named INT(10);
END-PR;

DSPLY ('RESULT:TWICE=' + %CHAR(Twice(21)));
DSPLY ('RESULT:GREET=' + Greet('RPG'));
CALLP Note();
DSPLY ('RESULT:NAMED=' + %CHAR(Named()));

// Multiplication by N, with and without spaces, is unaffected.
DSPLY ('RESULT:MUL=' + %CHAR(total*N) + ' ' + %CHAR(total * n));

*INLR = *ON;
RETURN;

DCL-PROC Twice;
  DCL-PI *N INT(10);
    v INT(10) VALUE;
  END-PI;
  RETURN v * 2;
END-PROC;

DCL-PROC Greet;
  DCL-PI
    *N VARCHAR(20);
    who VARCHAR(10) VALUE;
  END-PI;
  RETURN 'Hi ' + who;
END-PROC;

DCL-PROC Note;
  DCL-PI *N;
  END-PI;
  DSPLY 'RESULT:NOTE=called';
END-PROC;

// A named interface still works.
DCL-PROC Named;
  DCL-PI Named INT(10);
  END-PI;
  RETURN n * 7;
END-PROC;
