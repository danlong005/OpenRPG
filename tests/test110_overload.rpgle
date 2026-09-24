**FREE

// Test 110: OVERLOAD — a call goes to the one candidate its arguments fit.
// As on IBM i, the candidates must differ so that only one can fit — here by
// type family (number, date, character) and by number of parameters — and
// each returns the overloaded prototype's type.

CTL-OPT MAIN(main);

DCL-PR fmtNum VARCHAR(40);
  n PACKED(15:2) VALUE;
END-PR;

DCL-PR fmtDate VARCHAR(40);
  d DATE VALUE;
END-PR;

DCL-PR fmtText VARCHAR(40);
  s VARCHAR(30) CONST;
END-PR;

DCL-PR square INT(10);
  side INT(10) VALUE;
END-PR;

DCL-PR rectangle INT(10);
  width INT(10) VALUE;
  height INT(10) VALUE;
END-PR;

// An overloaded prototype is one statement: no parameters, no END-PR
DCL-PR format VARCHAR(40) OVERLOAD(fmtNum : fmtDate : fmtText);
DCL-PR area INT(10) OVERLOAD(square : rectangle);

DCL-PROC main;
  DCL-PI *N;
  END-PI;

  DCL-S count INT(10) INZ(42);
  DCL-S due DATE;

  due = %DATE('2024-01-15');

  DSPLY format(count);         // a number: fmtNum
  DSPLY format(3.5);           // any numeric type: fmtNum
  DSPLY format(due);           // a date: fmtDate
  DSPLY format('hello');       // a string: fmtText

  DSPLY %CHAR(area(4));        // one argument: square
  DSPLY %CHAR(area(3 : 5));    // two: rectangle
END-PROC;

DCL-PROC fmtNum;
  DCL-PI *N VARCHAR(40);
    n PACKED(15:2) VALUE;
  END-PI;
  RETURN 'number ' + %CHAR(n);
END-PROC;

DCL-PROC fmtDate;
  DCL-PI *N VARCHAR(40);
    d DATE VALUE;
  END-PI;
  RETURN 'date ' + %CHAR(d);
END-PROC;

DCL-PROC fmtText;
  DCL-PI *N VARCHAR(40);
    s VARCHAR(30) CONST;
  END-PI;
  RETURN 'text ' + s;
END-PROC;

DCL-PROC square;
  DCL-PI *N INT(10);
    side INT(10) VALUE;
  END-PI;
  RETURN side * side;
END-PROC;

DCL-PROC rectangle;
  DCL-PI *N INT(10);
    width INT(10) VALUE;
    height INT(10) VALUE;
  END-PI;
  RETURN width * height;
END-PROC;
