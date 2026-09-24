**FREE
// A call must fit one OVERLOAD candidate. A date fits neither a numeric nor
// a character parameter: IBM i reports RNF3245.
CTL-OPT MAIN(main);
DCL-PR fmtNum VARCHAR(40);
  n PACKED(15:2) VALUE;
END-PR;
DCL-PR fmtText VARCHAR(40);
  s VARCHAR(30) CONST;
END-PR;
DCL-PR format VARCHAR(40) OVERLOAD(fmtNum : fmtText);

DCL-PROC main;
  DCL-S due DATE;
  due = %DATE('2024-01-15');
  DSPLY format(due);
END-PROC;

DCL-PROC fmtNum;
  DCL-PI *N VARCHAR(40);
    n PACKED(15:2) VALUE;
  END-PI;
  RETURN %CHAR(n);
END-PROC;

DCL-PROC fmtText;
  DCL-PI *N VARCHAR(40);
    s VARCHAR(30) CONST;
  END-PI;
  RETURN s;
END-PROC;
