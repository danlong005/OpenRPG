     HDFTACTGRP(*NO)
      /COPY tests/fixed_copybook_dspec.rpgle
      /free
       greeting = 'Hello, copybook!';
       count = 7;
       DSPLY greeting;
       DSPLY %CHAR(count);
       *INLR = *ON;
      /end-free
