**FREE
// Every OVERLOAD candidate returns the overloaded prototype's type. fmtLen
// returns INT(10), not VARCHAR(40): IBM i reports RNF3244.
CTL-OPT MAIN(main);
DCL-PR fmtNum VARCHAR(40);
  n PACKED(15:2) VALUE;
END-PR;
DCL-PR fmtLen INT(10);
  s VARCHAR(30) CONST;
END-PR;
DCL-PR format VARCHAR(40) OVERLOAD(fmtNum : fmtLen);

DCL-PROC main;
  DSPLY format(1);
END-PROC;

DCL-PROC fmtNum;
  DCL-PI *N VARCHAR(40);
    n PACKED(15:2) VALUE;
  END-PI;
  RETURN %CHAR(n);
END-PROC;

DCL-PROC fmtLen;
  DCL-PI *N INT(10);
    s VARCHAR(30) CONST;
  END-PI;
  RETURN %LEN(s);
END-PROC;
