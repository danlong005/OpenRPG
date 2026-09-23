**FREE
// ds.field names a subfield only of a QUALIFIED data structure. Without
// QUALIFIED the subfield's name is just its own; IBM i reports the
// qualified form as an undefined name (RNF7030).
DCL-DS cust;
  name CHAR(10);
END-DS;
cust.name = 'ACME';
*INLR = *ON;
