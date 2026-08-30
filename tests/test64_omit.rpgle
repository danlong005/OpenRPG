**FREE
// Test 64: OPTIONS(*OMIT)
DCL-PR formatName VARCHAR(50);
  first VARCHAR(20) VALUE;
  middle VARCHAR(20) OPTIONS(*OMIT);
  last VARCHAR(20) VALUE;
END-PR;

DSPLY formatName('John' : *OMIT : 'Smith');

*INLR = *ON;

DCL-PROC formatName;
  DCL-PI formatName VARCHAR(50);
    first VARCHAR(20) VALUE;
    middle VARCHAR(20) OPTIONS(*OMIT);
    last VARCHAR(20) VALUE;
  END-PI;
  DCL-S result VARCHAR(50);

  IF %OMITTED(middle);
    result = first + ' ' + last;
  ELSE;
    result = first + ' ' + middle + ' ' + last;
  ENDIF;

  RETURN result;
END-PROC;

// Call with *OMIT