**FREE
// Test 52: Array BIFs - %MAXARR, %MINARR, %LOOKUPxx
// %LOOKUPLT/LE/GT/GE search an array in ASCEND or DESCEND order (IBM:
// RNF0592) and find the element nearest the search value.
DCL-S nums INT(10) DIM(5);
DCL-S sorted INT(10) DIM(5) ASCEND;
DCL-S idx INT(10);

nums(1) = 30;
nums(2) = 10;
nums(3) = 50;
nums(4) = 20;
nums(5) = 40;

sorted(1) = 10;
sorted(2) = 20;
sorted(3) = 30;
sorted(4) = 40;
sorted(5) = 50;

// %MAXARR - index of max element
idx = %MAXARR(nums);
DSPLY %CHAR(idx);

// %MINARR - index of min element
idx = %MINARR(nums);
DSPLY %CHAR(idx);

// %LOOKUPGE - the least element >= 25: 30, element 3
idx = %LOOKUPGE(25 : sorted);
DSPLY %CHAR(idx);

// %LOOKUPLT - the greatest element < 25: 20, element 2
idx = %LOOKUPLT(25 : sorted);
DSPLY %CHAR(idx);

*INLR = *ON;
