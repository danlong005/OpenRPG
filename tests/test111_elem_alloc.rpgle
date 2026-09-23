**FREE

// Test 111: %ELEM(*ALLOC) and %ELEM(*KEEP)

DCL-S nums INT(10) DIM(*VAR:10);
DCL-S i    INT(10);

// Expand capacity beyond DIM max
%ELEM(nums : *ALLOC) = 50;
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));  // 50
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 0

// Set 5 elements
%ELEM(nums) = 5;
FOR i = 1 TO 5;
  nums(i) = i * 2;
ENDFOR;
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 5
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));   // 50

// Shrink size with *KEEP — capacity is preserved
%ELEM(nums : *KEEP) = 3;
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 3
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));   // still 50

*INLR = *ON;
