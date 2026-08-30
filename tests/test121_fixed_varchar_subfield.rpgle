     HDFTACTGRP(*NO)
     DmyDS             DS                  QUALIFIED
     DvarField                       20A   VARYING
     DfixField                       20A
      /free
       myDS.varField = 'Hello';
       myDS.fixField = 'World';
       DSPLY myDS.varField;
       DSPLY myDS.fixField;
       *INLR = *ON;
      /end-free
