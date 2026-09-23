**FREE
// Prototype forward declarations
DCL-PR add INT(10);
  a INT(10) VALUE;
  b INT(10) VALUE;
END-PR;

DCL-PR factorial INT(10);
  n INT(10) VALUE;
END-PR;

DCL-PR greet VARCHAR(100);
  name VARCHAR(50) VALUE;
END-PR;

// Main program
DCL-S result INT(10);
DCL-S msg VARCHAR(100);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

result = add(10 : 20);
DSPLY %CHAR(result);

result = factorial(5);
DSPLY %CHAR(result);

msg = greet('RPG');
dspLine = msg;
DSPLY dspLine;

*INLR = *ON;

// Procedure definitions
DCL-PROC add;
  DCL-PI INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;

DCL-PROC factorial;
  DCL-PI INT(10);
    n INT(10) VALUE;
  END-PI;
  IF n <= 1;
    RETURN 1;
  ENDIF;
  RETURN n * factorial(n - 1);
END-PROC;

DCL-PROC greet;
  DCL-PI VARCHAR(100);
    name VARCHAR(50) VALUE;
  END-PI;
  DCL-S result VARCHAR(100);
  result = 'Hello, ' + name + '!';
  RETURN result;
END-PROC;
