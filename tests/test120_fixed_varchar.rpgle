     HDFTACTGRP(*NO)
     DvarName          S             20A   VARYING
     DfixName          S             20A
      /free
       DSPLY %CHAR(%LEN(varName));
       DSPLY %CHAR(%LEN(fixName));
       *INLR = *ON;
      /end-free
