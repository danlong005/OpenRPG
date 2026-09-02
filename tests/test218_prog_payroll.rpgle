     H*-----------------------------------------------------------------
     H* PAYREG  -  PAYROLL REGISTER
     H*-----------------------------------------------------------------
     H* PRICES OUT ONE WEEKLY PAY PERIOD.  ANYTHING PAST FORTY HOURS IS
     H* PAID AT TIME AND A HALF.  WITHHOLDING IS WORKED OUT BY NETPAY,
     H* CALLED ONCE PER EMPLOYEE THROUGH A NAMED PARAMETER LIST.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     D* EMPLOYEE TABLE
     DEMPNO            S              4A   DIM(5)
     DEMPNAM           S             10A   DIM(5)
     DHOURS            S              7P 2 DIM(5)
     DRATE             S              7P 2 DIM(5)
     DEXEMPT           S              3P 0 DIM(5)
     D* PARAMETERS PASSED TO NETPAY
     DWGROSS           S             11P 2
     DWEXEMP           S              3P 0
     DWTAX             S             11P 2
     DWNET             S             11P 2
     D* WORK AND ACCUMULATOR FIELDS
     DIX               S              5P 0
     DWHOURS           S              7P 2
     DWRATE            S              7P 2
     DREGHRS           S              7P 2
     DOTHRS            S              7P 2
     DREGPAY           S             11P 2
     DOTPAY            S             11P 2
     DOTRATE           S              7P 2
     DTOTGRS           S             13P 2
     DTOTTAX           S             13P 2
     DTOTNET           S             13P 2
     DTOTOT            S              9P 2
     DOTCNT            S              5P 0
     DPEDNUM           S              8P 0
     DPEDATE           S               D
     DPEDCHR           S             10A
     DRPTLIN           S             70A
     C*-----------------------------------------------------------------
     C* MAIN LINE
     C*-----------------------------------------------------------------
     C                   EXSR      INZSR1
     C                   FOR       IX = 1 TO 5
     C                   EXSR      EMPSR
     C                   ENDFOR
     C                   EXSR      TRLSR
     C                   RETURN
     C* THE PARAMETER LIST NETPAY IS CALLED WITH
     C     PAYARG        PLIST
     C                   PARM                    WGROSS
     C                   PARM                    WEXEMP
     C                   PARM                    WTAX
     C                   PARM                    WNET
     C*-----------------------------------------------------------------
     C* INZSR1  -  LOAD THE EMPLOYEE TABLE AND HEAD THE REGISTER
     C*-----------------------------------------------------------------
     C     INZSR1        BEGSR
     C                   EVAL      EMPNO(1) = 'E001'
     C                   EVAL      EMPNAM(1) = 'SMITH J'
     C                   Z-ADD     38.00         HOURS(1)
     C                   Z-ADD     22.50         RATE(1)
     C                   Z-ADD     2             EXEMPT(1)
     C                   EVAL      EMPNO(2) = 'E002'
     C                   EVAL      EMPNAM(2) = 'JONES A'
     C                   Z-ADD     45.50         HOURS(2)
     C                   Z-ADD     18.00         RATE(2)
     C                   Z-ADD     1             EXEMPT(2)
     C                   EVAL      EMPNO(3) = 'E003'
     C                   EVAL      EMPNAM(3) = 'BROWN K'
     C                   Z-ADD     40.00         HOURS(3)
     C                   Z-ADD     31.25         RATE(3)
     C                   Z-ADD     3             EXEMPT(3)
     C                   EVAL      EMPNO(4) = 'E004'
     C                   EVAL      EMPNAM(4) = 'DAVIS M'
     C                   Z-ADD     52.00         HOURS(4)
     C                   Z-ADD     15.50         RATE(4)
     C                   Z-ADD     0             EXEMPT(4)
     C                   EVAL      EMPNO(5) = 'E005'
     C                   EVAL      EMPNAM(5) = 'WILSON T'
     C                   Z-ADD     20.00         HOURS(5)
     C                   Z-ADD     27.00         RATE(5)
     C                   Z-ADD     4             EXEMPT(5)
     C                   Z-ADD     0             TOTGRS
     C                   Z-ADD     0             TOTTAX
     C                   Z-ADD     0             TOTNET
     C                   Z-ADD     0             TOTOT
     C                   Z-ADD     0             OTCNT
     C* THE PERIOD END DATE ARRIVES AS A PACKED YYYYMMDD NUMBER
     C                   Z-ADD     20260630      PEDNUM
     C     *ISO          MOVE      PEDNUM        PEDATE
     C     *ISO          MOVE      PEDATE        PEDCHR
     C                   EVAL      RPTLIN = 'PAYROLL REGISTER  PERIOD ENDING ' +
     C                             PEDCHR
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* EMPSR   -  PRICE ONE EMPLOYEE AND CALL FOR THE WITHHOLDING
     C*-----------------------------------------------------------------
     C     EMPSR         BEGSR
     C                   Z-ADD     HOURS(IX)     WHOURS
     C                   Z-ADD     RATE(IX)      WRATE
     C                   Z-ADD     0             OTHRS
     C                   Z-ADD     0             OTPAY
     C* SPLIT THE WEEK INTO STRAIGHT TIME AND OVERTIME
     C     WHOURS        COMP      40                                 35
     C                   IF        *IN35
     C                   Z-ADD     40            REGHRS
     C     WHOURS        SUB       40            OTHRS
     C                   ADD       1             OTCNT
     C                   ADD       OTHRS         TOTOT
     C                   ELSE
     C                   Z-ADD     WHOURS        REGHRS
     C                   ENDIF
     C     REGHRS        MULT      WRATE         REGPAY
     C* OVERTIME IS PAID AT TIME AND A HALF
     C     WRATE         MULT      1.5           OTRATE
     C     OTHRS         MULT      OTRATE        OTPAY
     C     REGPAY        ADD       OTPAY         WGROSS
     C                   Z-ADD     EXEMPT(IX)    WEXEMP
     C* HAND THE GROSS TO THE WITHHOLDING MODULE
     C                   CALL      'NETPAY'      PAYARG
     C                   ADD       WGROSS        TOTGRS
     C                   ADD       WTAX          TOTTAX
     C                   ADD       WNET          TOTNET
     C                   EVAL      RPTLIN = EMPNO(IX) + ' ' + EMPNAM(IX) + ' ' +
     C                             %EDITC(WGROSS:'1')
     C                   EVAL      RPTLIN = %TRIM(RPTLIN) + ' TAX ' +
     C                             %EDITC(WTAX:'1') + ' NET ' + %EDITC(WNET:'1')
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* TRLSR   -  REGISTER TOTALS
     C*-----------------------------------------------------------------
     C     TRLSR         BEGSR
     C                   EVAL      RPTLIN = '---- TOTALS ----'
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'GROSS ' + %EDITC(TOTGRS:'1') +
     C                             '  TAX ' + %EDITC(TOTTAX:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'NET   ' + %EDITC(TOTNET:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'OVERTIME HOURS ' +
     C                             %EDITC(TOTOT:'1') + ' ON ' + %CHAR(OTCNT) +
     C                             ' EMPLOYEES'
     C     RPTLIN        DSPLY
     C                   ENDSR
