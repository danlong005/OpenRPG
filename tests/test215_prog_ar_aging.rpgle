     H*-----------------------------------------------------------------
     H* ARAGE   -  ACCOUNTS RECEIVABLE AGING REPORT
     H*-----------------------------------------------------------------
     H* READS THE OPEN ITEM EXTRACT AND AGES EACH INVOICE INTO ONE OF
     H* FOUR BUCKETS RELATIVE TO THE AS-OF DATE.  PRINTS A CUSTOMER
     H* SUBTOTAL ON EACH CONTROL BREAK AND A GRAND TOTAL AT END OF FILE.
     H*
     H* THE EXTRACT IS ASSUMED SORTED BY CUSTOMER NUMBER.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     F* OPEN ITEM EXTRACT - PROGRAM DESCRIBED, 32 BYTE RECORDS
     FTESTFL215 U FA F   32        DISK
     D* AGING BUCKET ACCUMULATORS AND THEIR HEADINGS
     DBUCKET           S             11P 2 DIM(4)
     DBKTCNT           S              5P 0 DIM(4)
     DBKTNAM           S             12A   DIM(4)
     D* CUSTOMER NAME TABLE - LOADED BY THE INITIALISATION ROUTINE
     DCUSTID           S              6A   DIM(3)
     DCUSTNM           S             20A   DIM(3)
     D* CONTROL BREAK AND WORK FIELDS
     DPRVCUS           S              6A
     DCUSNAM           S             20A
     DCUSTOT           S             11P 2
     DGRDTOT           S             11P 2
     DCRDTOT           S             11P 2
     DASOF             S               D
     DINVDAT           S               D
     DDAYSOU           S              5P 0
     DBKTIX            S              5P 0
     DNAMIX            S              5P 0
     DIX               S              5P 0
     DRECCNT           S              5P 0
     DWRKCNT           S              5P 0
     DRPTLIN           S             52A
     DWRKAMT           S             13A
     DINVAMT           S             11P 2
     I* OPEN ITEM RECORD.  INDICATORS 20/21/22 FLAG THE SIGN OF THE
     I* INVOICE AMOUNT SO CREDIT MEMOS CAN BE REPORTED SEPARATELY.
     ITESTFL215 AA
     I                             A    1    6  CUSNO
     I                             A    7   13  INVNO
     I                             S   14   21 0INVDTE
     I                             S   22   32 0INVCTS              202122
     C* BUILD THE EXTRACT THIS RUN WILL READ BACK.
      /free
       CUSNO = 'C001';  INVNO = 'INV1001';
       INVDTE = 20260615;  INVCTS = 125000;
       WRITE TESTFL215;
       CUSNO = 'C001';  INVNO = 'INV1002';
       INVDTE = 20260520;  INVCTS = 34050;
       WRITE TESTFL215;
       CUSNO = 'C001';  INVNO = 'INV1003';
       INVDTE = 20260301;  INVCTS = 98075;
       WRITE TESTFL215;
       CUSNO = 'C002';  INVNO = 'INV2001';
       INVDTE = 20260628;  INVCTS = 7525;
       WRITE TESTFL215;
       CUSNO = 'C002';  INVNO = 'INV2002';
       INVDTE = 20260415;  INVCTS = 150000;
       WRITE TESTFL215;
       CUSNO = 'C002';  INVNO = 'INV2003';
       INVDTE = 20260630;  INVCTS = -9999;
       WRITE TESTFL215;
       CUSNO = 'C003';  INVNO = 'INV3001';
       INVDTE = 20260210;  INVCTS = 22500;
       WRITE TESTFL215;
       CUSNO = 'C003';  INVNO = 'INV3002';
       INVDTE = 20260601;  INVCTS = 6000;
       WRITE TESTFL215;
       CUSNO = 'C003';  INVNO = 'INV3003';
       INVDTE = 20260505;  INVCTS = 41010;
       WRITE TESTFL215;
       CUSNO = 'C003';  INVNO = 'INV3004';
       INVDTE = 20260325;  INVCTS = 187500;
       WRITE TESTFL215;
      /end-free
     C*-----------------------------------------------------------------
     C* MAIN LINE
     C*-----------------------------------------------------------------
     C                   EXSR      INZSR1
     C                   EXSR      HDGSR
     C                   READ      TESTFL215
     C                   DOW       NOT %EOF(TESTFL215)
     C* CONTROL BREAK ON CUSTOMER NUMBER
     C     CUSNO         COMP      PRVCUS                                 31
     C  N31              EXSR      BRKSR
     C                   EXSR      AGESR
     C                   READ      TESTFL215
     C                   ENDDO
     C* FINAL BREAK AND TOTALS
     C                   EXSR      BRKSR
     C                   EXSR      TOTSR
     C                   RETURN
     C*-----------------------------------------------------------------
     C* INZSR1  -  LOAD TABLES, CLEAR ACCUMULATORS, SET THE AS-OF DATE
     C*-----------------------------------------------------------------
     C     INZSR1        BEGSR
     C     *ISO          MOVE      '2026-06-30'  ASOF
     C                   EVAL      BKTNAM(1) = 'Current'
     C                   EVAL      BKTNAM(2) = '31-60 days'
     C                   EVAL      BKTNAM(3) = '61-90 days'
     C                   EVAL      BKTNAM(4) = 'Over 90'
     C                   EVAL      CUSTID(1) = 'C001'
     C                   EVAL      CUSTNM(1) = 'Acme Manufacturing'
     C                   EVAL      CUSTID(2) = 'C002'
     C                   EVAL      CUSTNM(2) = 'Bolt & Nut Supply'
     C                   EVAL      CUSTID(3) = 'C003'
     C                   EVAL      CUSTNM(3) = 'Consolidated Tool'
     C                   FOR       IX = 1 TO 4
     C                   Z-ADD     0             BUCKET(IX)
     C                   Z-ADD     0             BKTCNT(IX)
     C                   ENDFOR
     C                   Z-ADD     0             GRDTOT
     C                   Z-ADD     0             CUSTOT
     C                   Z-ADD     0             CRDTOT
     C                   Z-ADD     0             RECCNT
     C                   EVAL      PRVCUS = *BLANKS
     C* 41 MARKS THE FIRST BREAK, WHICH HAS NO PRIOR CUSTOMER TO TOTAL
     C                   EVAL      *IN41 = *ON
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* HDGSR   -  REPORT HEADING
     C*-----------------------------------------------------------------
     C     HDGSR         BEGSR
     C                   EVAL      RPTLIN = 'A/R AGING AS OF 2026-06-30'
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = '--------------------------------'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* AGESR   -  AGE ONE OPEN ITEM AND ADD IT TO THE RIGHT BUCKET
     C*-----------------------------------------------------------------
     C     AGESR         BEGSR
     C                   ADD       1             RECCNT
     C* THE EXTRACT CARRIES WHOLE CENTS; THE REPORT WORKS IN DOLLARS
     C                   EVAL      INVAMT = INVCTS / 100
     C* CONVERT THE PACKED YYYYMMDD INVOICE DATE TO A REAL DATE
     C     *ISO          MOVE      INVDTE        INVDAT
     C                   EVAL      DAYSOU = %DIFF(ASOF:INVDAT:*DAYS)
     C* CLASSIFY INTO AN AGING BUCKET
     C                   SELECT
     C                   WHEN      DAYSOU <= 30
     C                   Z-ADD     1             BKTIX
     C                   WHEN      DAYSOU <= 60
     C                   Z-ADD     2             BKTIX
     C                   WHEN      DAYSOU <= 90
     C                   Z-ADD     3             BKTIX
     C                   OTHER
     C                   Z-ADD     4             BKTIX
     C                   ENDSL
     C                   ADD       INVAMT        BUCKET(BKTIX)
     C                   ADD       1             BKTCNT(BKTIX)
     C                   ADD       INVAMT        CUSTOT
     C                   ADD       INVAMT        GRDTOT
     C* INDICATOR 21 IS SET BY THE I-SPEC WHEN THE AMOUNT IS NEGATIVE
     C   21              ADD       INVAMT        CRDTOT
     C* DETAIL LINE
     C                   EVAL      WRKAMT = %EDITC(INVAMT:'1')
     C                   EVAL      RPTLIN = INVNO + ' ' + %CHAR(DAYSOU) +
     C                             ' ' + WRKAMT + ' ' + BKTNAM(BKTIX)
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* BRKSR   -  CUSTOMER CONTROL BREAK.  SKIPS THE VERY FIRST CALL,
     C*            WHEN THERE IS NO PREVIOUS CUSTOMER TO TOTAL.
     C*-----------------------------------------------------------------
     C     BRKSR         BEGSR
     C   41              GOTO      BRKEND
     C* LOOK THE CUSTOMER NAME UP IN THE TABLE LOADED AT INITIALISATION
     C                   EVAL      NAMIX = %LOOKUP(%TRIM(PRVCUS):CUSTID)
     C                   IF        NAMIX > 0
     C                   EVAL      CUSNAM = CUSTNM(NAMIX)
     C                   ELSE
     C                   EVAL      CUSNAM = '** UNKNOWN **'
     C                   ENDIF
     C                   EVAL      RPTLIN = '  TOTAL ' + PRVCUS + ' ' +
     C                             %TRIM(CUSNAM) + ' ' + %EDITC(CUSTOT:'1')
     C     RPTLIN        DSPLY
     C                   Z-ADD     0             CUSTOT
     C     BRKEND        TAG
     C                   EVAL      *IN41 = *OFF
     C                   EVAL      PRVCUS = CUSNO
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* TOTSR   -  AGING SUMMARY AND GRAND TOTALS
     C*-----------------------------------------------------------------
     C     TOTSR         BEGSR
     C                   EVAL      RPTLIN = '--------------------------------'
     C     RPTLIN        DSPLY
     C                   FOR       IX = 1 TO 4
     C                   Z-ADD     BKTCNT(IX)    WRKCNT
     C                   EVAL      RPTLIN = BKTNAM(IX) + ' ' +
     C                             %CHAR(WRKCNT) + ' ' +
     C                             %EDITC(BUCKET(IX):'1')
     C     RPTLIN        DSPLY
     C                   ENDFOR
     C                   EVAL      RPTLIN = 'ITEMS READ   ' + %CHAR(RECCNT)
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'CREDIT MEMOS ' + %EDITC(CRDTOT:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'GRAND TOTAL  ' + %EDITC(GRDTOT:'1')
     C     RPTLIN        DSPLY
     C                   ENDSR
     O* EXTRACT RECORD IMAGE USED BY THE SEEDING WRITE ABOVE
     OTESTFL215
     O                       CUSNO                6
     O                       INVNO               13
     O                       INVDTE              21
     O                       INVCTS              32
