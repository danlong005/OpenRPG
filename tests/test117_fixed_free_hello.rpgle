     HDFTACTGRP(*NO)
     Dgreeting                  20     A
     Dcount                     10     I0
      /free
  greeting = 'Hello, world!';
  count = 42;
  DSPLY greeting;
  DSPLY %CHAR(count);
  *INLR = *ON;
      /end-free
