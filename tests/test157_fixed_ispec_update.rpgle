     HDFTACTGRP(*NO)
     FTESTFL157 UF A F   20        DISK
     ITESTFL157 AA
     I                             A    1   20  NOTE
     OTESTFL157 D
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
