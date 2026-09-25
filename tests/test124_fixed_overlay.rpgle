     HDFTACTGRP(*NO)
     Daddress          DS                  QUALIFIED
     DfullAddr                       50A
     Dcity                           20A   OVERLAY(fullAddr)
     Dstate                           2A   OVERLAY(fullAddr:21)
     Dzip                            10A   OVERLAY(fullAddr:23)
     Drecord           DS                  QUALIFIED
     Did                       1      4I 0
     Dname                     5     24A
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
