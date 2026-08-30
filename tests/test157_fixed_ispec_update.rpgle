     HDFTACTGRP(*NO)
     FTESTFL157       20           DISK
     ITESTFL157
     I                             A    1   20  NOTE
     OTESTFL157
     O                       NOTE                20
      /free
  NOTE = 'original';
  WRITE TESTFL157;
      /end-free
     C                   READ      TESTFL157
      /free
  NOTE = 'updated!';
      /end-free
     C                   UPDATE    TESTFL157
     C     'done'        DSPLY
     C                   RETURN
