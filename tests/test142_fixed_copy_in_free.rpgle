     HDFTACTGRP(*NO)
     Dlocal_val                 10     I0
      /free
  /COPY tests/copybook1.rpgle
  local_val = shared_val + 1;
  DSPLY shared_msg;
  DSPLY %CHAR(local_val);
  *INLR = *ON;
      /end-free
