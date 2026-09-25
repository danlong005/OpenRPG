**FREE
// %LOOKUPGE finds the element nearest the search value, which needs the
// array in order: IBM i requires ASCEND or DESCEND on it (RNF0592).
DCL-S nums INT(10) DIM(3);
DCL-S idx INT(10);
nums(1) = 30;
nums(2) = 10;
nums(3) = 20;
idx = %LOOKUPGE(15 : nums);
DSPLY %CHAR(idx);
*INLR = *ON;
