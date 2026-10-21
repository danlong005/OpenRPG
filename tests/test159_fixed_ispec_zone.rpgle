     H*Record identification codes with code part Z (zone) and D (digit)
     H*compare the EBCDIC zone or digit half of a record byte. As a Z
     H*test character, '&' also matches zone C (A-I) and '-' zone D
     H*(J-R). The first record type whose tests match is the one read.
     H*Every expected line was checked on PUB400 (2026-10-21).
     HDFTACTGRP(*NO)
     FTESTFL159 UF A F   10        DISK
     DC                S              1A
     DR                S             20A
     I* 01: digit 5 -- '5' (x'F5') and 'E' (x'C5')
     ITESTFL159 AA  01    1 D5
     I                             A    1    1  CH
     I* 02: zone of '&' -- '&' and '*' (x'5_'), and A-I (x'C_')
     ITESTFL159 AB  02    1 Z&
     I                             A    1    1  CH
     I* 03: zone of '-' -- '-' (x'60'), and J-R (x'D_')
     ITESTFL159 AC  03    1 Z-
     I                             A    1    1  CH
     I* 04: anything else
     ITESTFL159 AD  04
     I                             A    1    1  CH
      /free
       C = 'A';
       EXCEPT;
       C = '&';
       EXCEPT;
       C = '*';
       EXCEPT;
       C = 'J';
       EXCEPT;
       C = '-';
       EXCEPT;
       C = '5';
       EXCEPT;
       C = 'E';
       EXCEPT;
       C = '1';
       EXCEPT;
       C = 'S';
       EXCEPT;
      /end-free
     C                   EVAL      *IN01 = *OFF
     C                   EVAL      *IN02 = *OFF
     C                   EVAL      *IN03 = *OFF
     C                   EVAL      *IN04 = *OFF
     C                   READ      TESTFL159
     C                   DOW       NOT %EOF(TESTFL159)
     C                   EVAL      R = CH + ' ' + %CHAR(*IN01) + %CHAR(*IN02)
     C                             + %CHAR(*IN03) + %CHAR(*IN04)
     C     R             DSPLY
     C                   EVAL      *IN01 = *OFF
     C                   EVAL      *IN02 = *OFF
     C                   EVAL      *IN03 = *OFF
     C                   EVAL      *IN04 = *OFF
     C                   READ      TESTFL159
     C                   ENDDO
     C                   RETURN
     OTESTFL159 EADD
     O                       C                    1
