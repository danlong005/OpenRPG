**FREE
DCL-S total INT(10);
DCL-S x INT(10);

total = 0;

// Call subroutines
EXSR addTen;
EXSR addTen;
EXSR addTen;
EXSR showTotal;

// Subroutine with condition
x = 5;
EXSR doubleIfSmall;
DSPLY %CHAR(x);

*INLR = *ON;

// Subroutines come after all other calculations (IBM i: RNF5005)
BEGSR addTen;
  total = total + 10;
ENDSR;

BEGSR showTotal;
  DSPLY %CHAR(total);
ENDSR;

BEGSR doubleIfSmall;
  IF x < 10;
    x = x * 2;
  ENDIF;
ENDSR;
