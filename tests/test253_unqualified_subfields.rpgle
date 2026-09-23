**FREE
// A subfield of a DS without QUALIFIED is referenced by its bare name.
//
// The subfield lived inside the DS's generated struct, and a bare
// reference compiled to an undeclared C++ name. In RPG an unqualified
// DS's subfields are ordinary names, and most legacy code uses them that
// way; DS.field works too.
DCL-DS cust;
  name CHAR(10);
  bal  PACKED(7:2);
END-DS;

DCL-DS ordr PREFIX(o_);
  qty INT(10);
END-DS;

DCL-PR Bump;
END-PR;

name = 'ACME';
bal = 12.345;
DSPLY ('RESULT:BARE=[' + name + '] ' + %CHAR(bal) + ' ' + %CHAR(%LEN(name)));
DSPLY ('RESULT:QUAL=[' + cust.name + ']');
o_qty = 5;
Bump();
DSPLY ('RESULT:PREFIX=' + %CHAR(o_qty));
*INLR = *ON;
RETURN;

// A subprocedure sees the unqualified subfields as module globals.
DCL-PROC Bump;
  o_qty = o_qty + 1;
  bal = bal * 2;
  DSPLY ('RESULT:PROC=' + %CHAR(bal));
END-PROC;
