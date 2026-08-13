     HDFTACTGRP(*NO)
     DvarName                   20     A   VARYING
     DfixName                   20     A
      /free
  DSPLY %CHAR(%LEN(varName));
  DSPLY %CHAR(%LEN(fixName));
  *INLR = *ON;
      /end-free
