     H*A PROGRAM-DESCRIBED FILE HAS NO RECORD FORMAT OF ITS OWN, SO WRITE
     H*NEEDS A DATA STRUCTURE HOLDING THE RECORD. IBM I REJECTS WRITE FILE
     H*ALONE (RNF5191); THE O-SPEC RECORD IS WRITTEN WITH EXCEPT.
     FTESTFL158 O    F   20        DISK
     DAMT              S             10S 0
      /free
       AMT = 1;
       WRITE TESTFL158;
      /end-free
     C                   RETURN
     OTESTFL158 E
     O                       AMT                 10
