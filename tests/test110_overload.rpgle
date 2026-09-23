**FREE

// Test 110: OVERLOAD — dispatch to typed implementations by argument type

CTL-OPT MAIN(main);

// Specific implementations
DCL-PR absInt INT(10);
  n INT(10) VALUE;
END-PR;

DCL-PR absFloat FLOAT(8);
  n FLOAT(8) VALUE;
END-PR;

DCL-PR addInt INT(10);
  a INT(10) VALUE;
  b INT(10) VALUE;
END-PR;

DCL-PR addFloat FLOAT(8);
  a FLOAT(8) VALUE;
  b FLOAT(8) VALUE;
END-PR;

// Overloaded generics
DCL-PR abs OVERLOAD(absInt : absFloat);
END-PR;

DCL-PR add OVERLOAD(addInt : addFloat);
END-PR;

DCL-PROC main;
  DCL-PI main;
  END-PI;

  DCL-S i   INT(10);
  DCL-S f   FLOAT(8);

  // abs dispatches by argument type
  i = abs(-7);
  DSPLY ('abs(-7)=' + %CHAR(i));

  f = abs(-3.0);
  DSPLY ('abs(-3.0)=' + %CHAR(%INT(f)));

  // add dispatches by argument type
  i = add(10 : 32);
  DSPLY ('add(10:32)=' + %CHAR(i));

  f = add(1.5 : 2.5);
  DSPLY ('add(1.5:2.5)=' + %CHAR(%INT(f)));

END-PROC;

DCL-PROC absInt EXPORT;
  DCL-PI absInt INT(10);
    n INT(10) VALUE;
  END-PI;
  IF n < 0;
    RETURN -n;
  ENDIF;
  RETURN n;
END-PROC;

DCL-PROC absFloat EXPORT;
  DCL-PI absFloat FLOAT(8);
    n FLOAT(8) VALUE;
  END-PI;
  IF n < 0;
    RETURN -n;
  ENDIF;
  RETURN n;
END-PROC;

DCL-PROC addInt EXPORT;
  DCL-PI addInt INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;

DCL-PROC addFloat EXPORT;
  DCL-PI addFloat FLOAT(8);
    a FLOAT(8) VALUE;
    b FLOAT(8) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;
