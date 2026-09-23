**FREE
// A subfield of a DS without QUALIFIED is referenced by its bare name.
//
// The subfield lived inside the DS's generated struct, and a bare
// reference compiled to an undeclared C++ name. In RPG an unqualified
// DS's subfields are ordinary names, and most legacy code uses them that
// way. (DS.field is only for a QUALIFIED DS — rpgc rejects it otherwise,
// as IBM i does: test 257.)
DCL-DS cust;
  name CHAR(10);
  bal  PACKED(7:2);
END-DS;

DCL-DS ordr;
  qty INT(10);
END-DS;

DCL-PR Bump;
END-PR;

name = 'ACME';
bal = 12.345;
DSPLY ('RESULT:BARE=[' + name + '] ' + %CHAR(bal) + ' ' + %CHAR(%LEN(name)));
qty = 5;
Bump();
DSPLY ('RESULT:QTY=' + %CHAR(qty));
*INLR = *ON;
RETURN;

// A subprocedure sees the unqualified subfields as module globals.
DCL-PROC Bump;
  qty = qty + 1;
  bal = bal * 2;
  DSPLY ('RESULT:PROC=' + %CHAR(bal));
END-PROC;
