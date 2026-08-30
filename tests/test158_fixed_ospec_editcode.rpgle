     HDFTACTGRP(*NO)
     FTESTFL158 O    F   20        DISK
     DAMT              S             10S
      /free
       AMT = 123456;
       WRITE TESTFL158;
      /end-free
     C                   RETURN
     OTESTFL158 D
     O                       AMT           1     10
