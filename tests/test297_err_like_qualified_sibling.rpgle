**FREE
// In a QUALIFIED data structure the subfields are not names of their own,
// so LIKE names a sibling as ds.field. IBM i rejects LIKE(field) alone
// (RNF7030).
DCL-DS invoice QUALIFIED;
  unitPrice PACKED(9:2);
  price LIKE(unitPrice);
END-DS;
invoice.price = 1;
DSPLY %CHAR(invoice.price);
*INLR = *ON;
