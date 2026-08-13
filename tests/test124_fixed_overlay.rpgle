     HDFTACTGRP(*NO)
     Daddress          DS                  QUALIFIED
     DfullAddr                  50     A
     Dcity                      20     A   OVERLAY(fullAddr)
     Dstate                     2      A   OVERLAY(fullAddr:21)
     Dzip                       10     A   OVERLAY(fullAddr:23)
     Drecord           DS                  QUALIFIED
     Did                        10     I0  POS(1)
     Dname                      20     A   POS(5)
      /free
  address.city = 'Minneapolis';
  address.state = 'MN';
  address.zip = '55401';
  DSPLY %TRIM(address.city);
  DSPLY address.state;
  DSPLY %TRIM(address.zip);
  record.id = 1;
  record.name = 'Test Record';
  DSPLY %CHAR(record.id);
  DSPLY %TRIM(record.name);
  *INLR = *ON;
      /end-free
