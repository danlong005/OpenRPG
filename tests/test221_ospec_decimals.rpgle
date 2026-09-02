     HDFTACTGRP(*NO)
     F*REGRESSION: A NUMERIC FIELD WRITTEN BY AN O-SPEC MUST COME
     F*BACK FROM THE I-SPEC WITH THE SAME VALUE.  THE WRITE SIDE
     F*ONCE IGNORED THE DECLARED DECIMAL POSITIONS, SO EVERY ROUND
     F*TRIP DIVIDED THE AMOUNT BY 10**DECIMALS.
     FTESTFL221 UF A F   30        DISK
     DSHOW             S              9S 2
     DSHOW3            S              9S 3
     DRPTLIN           S             60A
     I*ONE FORMAT: A KEY, A 2-DECIMAL AMOUNT, A 3-DECIMAL RATE.
     ITESTFL221 AA
     I                             A    1    6  ITEMNO
     I                             S    7   17 2AMOUNT
     I                             S   18   24 3RATE
     I                             A   25   30  UOM
      /free
       // build the extract the C-specs then read back
       itemno = 'WIDGET';  amount = 1250.00;  rate = 1.375;  uom = 'EACH  ';
       WRITE TESTFL221;
       itemno = 'BOLT  ';  amount = 0.05;     rate = 0.001;  uom = 'BOX   ';
       WRITE TESTFL221;
       itemno = 'MAXVAL';  amount = 99999999.99; rate = 9999.999;
       uom = 'CS    ';
       WRITE TESTFL221;
      /end-free
     C*READ EACH RECORD BACK AND PROVE THE VALUE SURVIVED
     C                   READ      TESTFL221
     C                   DOW       NOT %EOF(TESTFL221)
     C                   Z-ADD     AMOUNT        SHOW
     C                   Z-ADD     RATE          SHOW3
     C                   EVAL      RPTLIN = ITEMNO + ' ' + %EDITC(SHOW:'1') +
     C                             ' ' + %EDITC(SHOW3:'1') + ' ' + UOM
     C     RPTLIN        DSPLY
     C                   READ      TESTFL221
     C                   ENDDO
     C                   RETURN
     O*THE WRITE SIDE OF THE ROUND TRIP
     OTESTFL221
     O                       ITEMNO               6
     O                       AMOUNT              17
     O                       RATE                24
     O                       UOM                 30
