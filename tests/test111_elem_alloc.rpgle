**FREE

// Test 111: %ELEM(*ALLOC) and %ELEM(*KEEP)

DCL-S nums INT(10) DIM(*VAR:100);
DCL-S i    INT(10);

// A DIM(*VAR) array is allocated to its maximum: on IBM i %ELEM(*ALLOC)
// reports 100 here, before and after this assignment. The allocation, like
// the element count, cannot be set above the DIM maximum (RNF7563); test 284
// is that.
%ELEM(nums : *ALLOC) = 50;
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));  // 100
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 0

// Set 5 elements
%ELEM(nums) = 5;
FOR i = 1 TO 5;
  nums(i) = i * 2;
ENDFOR;
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 5
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));   // 100

// Shrink size with *KEEP — the allocation is unchanged
%ELEM(nums : *KEEP) = 3;
DSPLY ('size=' + %CHAR(%ELEM(nums)));           // 3
DSPLY ('cap=' + %CHAR(%ELEM(nums : *ALLOC)));   // still 100

*INLR = *ON;
