     HDFTACTGRP(*NO)
     Dgreeting         S             20A
     Dcount            S             10I 0
      /free
       greeting = 'Hello, world!';
       count = 42;
       DSPLY greeting;
       DSPLY %CHAR(count);
       *INLR = *ON;
      /end-free
