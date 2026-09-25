     HDFTACTGRP(*NO)
     FTESTFL157 UF A F   20        DISK
     ITESTFL157 AA
     I                             A    1   20  NOTE
      /free
       NOTE = 'original';
       EXCEPT NEWNOTE;
      /end-free
     C                   READ      TESTFL157
      /free
       NOTE = 'updated!';
      /end-free
     C                   EXCEPT    CHGNOTE
     C     'done'        DSPLY
     C                   RETURN
     OTESTFL157 EADD         NEWNOTE
     O                       NOTE                20
     OTESTFL157 E            CHGNOTE
     O                       NOTE                20
