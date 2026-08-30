     HDFTACTGRP(*NO)
     Ditems            DS                  QUALIFIED DIM(3)
     Ddesc                           20A   VARYING
     Dqty                            10I 0
      /free
  items(1).desc = 'Widget';
  items(1).qty = 10;
  items(2).desc = 'Gadget';
  items(2).qty = 20;
  items(3).desc = 'Doohickey';
  items(3).qty = 5;
  DSPLY items(2).desc;
  DSPLY %CHAR(items(3).qty);
  *INLR = *ON;
      /end-free
