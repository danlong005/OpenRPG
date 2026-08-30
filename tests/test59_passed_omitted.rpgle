**FREE
// Test 59: %PASSED and %OMITTED
DCL-PR greet VARCHAR(50);
  name VARCHAR(20) VALUE;
  title VARCHAR(10) VALUE OPTIONS(*NOPASS);
END-PR;

DSPLY greet('World');
DSPLY greet('Smith' : 'Dr.');

*INLR = *ON;

DCL-PROC greet;
  DCL-PI greet VARCHAR(50);
    name VARCHAR(20) VALUE;
    title VARCHAR(10) VALUE OPTIONS(*NOPASS);
  END-PI;
  DCL-S result VARCHAR(50);

  IF %PASSED(title);
    result = title + ' ' + name;
  ELSE;
    result = 'Hello ' + name;
  ENDIF;

  RETURN result;
END-PROC;
