**FREE
// Test 54: Memory/Pointer BIFs - %PADDR, %PROC

DCL-PR myFunc INT(10);
  x INT(10) VALUE;
END-PR;

DCL-S pName VARCHAR(50);

// Test %PROC inside a procedure
DCL-S result VARCHAR(50);

// %PROC - current procedure name (in main context)
pName = %PROC;
DSPLY pName;

result = getMyName();
DSPLY result;

*INLR = *ON;

DCL-PROC myFunc;
  DCL-PI myFunc INT(10);
    x INT(10) VALUE;
  END-PI;
  RETURN x * 2;
END-PROC;

DCL-PROC getMyName;
  DCL-PI getMyName VARCHAR(50);
  END-PI;
  RETURN %PROC;
END-PROC;
