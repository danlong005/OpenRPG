     HDFTACTGRP(*NO)
     Dorder            DS                  QUALIFIED
     DlineTotals                     10P 2 DIM(3)
     Dcount                          10I 0
      /free
  order.lineTotals(1) = 12.50;
  order.lineTotals(2) = 7.25;
  order.lineTotals(3) = 100;
  order.count = 3;
  DSPLY %CHAR(order.lineTotals(2));
  DSPLY %CHAR(order.lineTotals(1) + order.lineTotals(3));
  DSPLY %CHAR(order.count);
  *INLR = *ON;
      /end-free
