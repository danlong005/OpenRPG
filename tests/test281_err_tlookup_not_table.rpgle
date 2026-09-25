**FREE
// %TLOOKUP searches a table, an array whose name begins with TAB. IBM i
// rejects any other array (RNF0597); %LOOKUP searches any array.
DCL-S codes CHAR(3) DIM(3);
DCL-S found IND;
codes(1) = 'LAX';
found = %TLOOKUP('LAX' : codes);
DSPLY %CHAR(found);
*INLR = *ON;
