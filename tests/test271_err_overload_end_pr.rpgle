**FREE
// An OVERLOAD prototype has no parameters, so it is a single statement:
// END-PR after it is an error on IBM i (RNF3551).
CTL-OPT MAIN(main);
DCL-PR fmtNum VARCHAR(40);
  n PACKED(15:2) VALUE;
END-PR;
DCL-PR fmtText VARCHAR(40);
  s VARCHAR(30) CONST;
END-PR;
DCL-PR format VARCHAR(40) OVERLOAD(fmtNum : fmtText);
END-PR;

DCL-PROC main;
  DSPLY format(1);
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
