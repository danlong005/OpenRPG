     HDFTACTGRP(*NO)
     FTESTFL156 UF A F   10        DISK
     ITESTFL156 AA
     I                             S    1   10 0AMT                 010203
      /free
       AMT = 50;
       WRITE TESTFL156;
       AMT = -50;
       WRITE TESTFL156;
       AMT = 0;
       WRITE TESTFL156;
      /end-free
     C                   READ      TESTFL156
     C                   DOW       NOT %EOF(TESTFL156)
     C                   IF        *IN01
     C     'plus'        DSPLY
     C                   ENDIF
     C                   IF        *IN02
     C     'minus'       DSPLY
     C                   ENDIF
     C                   IF        *IN03
     C     'zero'        DSPLY
     C                   ENDIF
     C                   READ      TESTFL156
     C                   ENDDO
     C                   RETURN
     OTESTFL156 D
     O                       AMT                 10
