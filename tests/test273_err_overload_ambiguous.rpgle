**FREE
// A number passed by VALUE fits any numeric parameter, so an INT(10)
// candidate and a FLOAT(8) one both fit abs(-7). IBM i does not pick the
// closer type; it reports the call as ambiguous (RNF3246).
CTL-OPT MAIN(main);
DCL-PR absInt FLOAT(8);
  n INT(10) VALUE;
END-PR;
DCL-PR absFloat FLOAT(8);
  n FLOAT(8) VALUE;
END-PR;
DCL-PR abs FLOAT(8) OVERLOAD(absInt : absFloat);

DCL-PROC main;
  DSPLY %CHAR(%INT(abs(-7)));
END-PROC;

DCL-PROC absInt;
  DCL-PI *N FLOAT(8);
    n INT(10) VALUE;
  END-PI;
  RETURN %ABS(n);
END-PROC;

DCL-PROC absFloat;
  DCL-PI *N FLOAT(8);
    n FLOAT(8) VALUE;
  END-PI;
  RETURN %ABS(n);
END-PROC;
