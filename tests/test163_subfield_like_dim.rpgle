**FREE
// Per-subfield LIKE(...) and DIM(...) — item #5
DCL-DS invoice QUALIFIED;
  unitPrice PACKED(9:2);
  qty INT(5);
  price LIKE(unitPrice);
  lineTotals PACKED(10:2) DIM(3);
END-DS;

invoice.unitPrice = 19.99;
invoice.qty = 3;
invoice.price = invoice.unitPrice * invoice.qty;
invoice.lineTotals(1) = 12.50;
invoice.lineTotals(2) = 7.25;
invoice.lineTotals(3) = invoice.price;

DSPLY %CHAR(invoice.price);
DSPLY %CHAR(invoice.lineTotals(2));
DSPLY %CHAR(invoice.lineTotals(1) + invoice.lineTotals(3));

*INLR = *ON;
