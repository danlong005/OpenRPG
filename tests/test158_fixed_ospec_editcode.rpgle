     HDFTACTGRP(*NO)
     FTESTFL158 O    F   20        DISK
     DAMT              S             10S 0
      /free
       AMT = 123456;
       EXCEPT;
      /end-free
     C                   RETURN
     OTESTFL158 E
     O                       AMT           1     13
