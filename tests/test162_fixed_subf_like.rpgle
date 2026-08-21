     HDFTACTGRP(*NO)
     Dinvoice          DS                  QUALIFIED
     DunitPrice                 9      P2
     Dqty                       5      I0
     Dprice                                LIKE(unitPrice)
      /free
  invoice.unitPrice = 19.99;
  invoice.qty = 3;
  invoice.price = invoice.unitPrice * invoice.qty;
  DSPLY %CHAR(invoice.price);
  DSPLY %CHAR(invoice.qty);
  *INLR = *ON;
      /end-free
