     H*-----------------------------------------------------------------
     H* GLPOST  -  GENERAL LEDGER BATCH EDIT AND POSTING REGISTER
     H*-----------------------------------------------------------------
     H* THE JOURNAL INTERFACE FILE CARRIES TWO RECORD TYPES IN ONE
     H* PHYSICAL LAYOUT - AN 'H' BATCH HEADER CARRYING THE EXPECTED
     H* CONTROL TOTAL, FOLLOWED BY ITS 'D' JOURNAL DETAIL LINES.
     H*
     H* EACH BATCH IS EDITED FOR DEBIT/CREDIT BALANCE AND AGAINST THE
     H* CONTROL TOTAL ON ITS HEADER.  AMOUNTS ARE CARRIED AS WHOLE
     H* CENTS, AS INTERFACE FILES CONVENTIONALLY DO.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
     FTESTFL216 U FA F   48        DISK
     D* BATCH ACCUMULATORS
     DDRTOT            S             11P 0
     DCRTOT            S             11P 0
     DVARNCE           S             11P 0
     DSAVEXP           S             11P 0
     DVARPCT           S              7P 2
     D* RUN ACCUMULATORS BY ACCOUNT CLASS
     DCLSTOT           S             13P 0 DIM(3)
     DCLSNAM           S             14A   DIM(3)
     D* CONTROL AND WORK FIELDS
     DCURBAT           S              6A
     DACCT1            S              1A
     DCLSIX            S              5P 0
     DIX               S              5P 0
     DBATCNT           S              5P 0
     DLINCNT           S              5P 0
     DERRCNT           S              5P 0
     DWRKNUM           S             13P 0
     DWRKDLR           S             13P 2
     DRPTLIN           S             60A
     D* THE ONLY IMAGE FIELD THE I-SPECS DO NOT ALREADY DEFINE
     DRECTYP           S              1A
     I* BATCH HEADER - POSITION 1 HOLDS 'H'.  INDICATOR 01.
     ITESTFL216 AA  01    1 CH
     I                             A    2    7  BATNO
     I                             S   15   25 0EXPTOT
     I                             A   26   48  DESCR
     I* JOURNAL DETAIL - POSITION 1 HOLDS 'D'.  INDICATOR 02.
     I* INDICATORS 25/26 FLAG THE SIGN OF THE LINE AMOUNT.
     ITESTFL216 AA  02    1 CD
     I                             A    2    7  BATNO
     I                             A    8   13  ACCTNO
     I                             A   14   14  DRCR
     I                             S   15   25 0AMTCTS              2526
     I                             A   26   48  DESCR
     C* BUILD THE INTERFACE FILE THIS RUN WILL EDIT.
      /free
       RECTYP = 'H';  BATNO = 'B00100';
       ACCTNO = '';  DRCR = ' ';
       AMTCTS = 250000;  DESCR = 'APRIL ACCRUALS';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00100';
       ACCTNO = '400100';  DRCR = 'D';
       AMTCTS = 150000;  DESCR = 'RENT EXPENSE';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00100';
       ACCTNO = '400200';  DRCR = 'D';
       AMTCTS = 100000;  DESCR = 'UTILITIES';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00100';
       ACCTNO = '300100';  DRCR = 'C';
       AMTCTS = 250000;  DESCR = 'ACCRUED LIABILITY';
       WRITE TESTFL216;
       RECTYP = 'H';  BATNO = 'B00200';
       ACCTNO = '';  DRCR = ' ';
       AMTCTS = 100000;  DESCR = 'MISC ADJUSTMENTS';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00200';
       ACCTNO = '400100';  DRCR = 'D';
       AMTCTS = 60000;  DESCR = 'RENT TRUE-UP';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00200';
       ACCTNO = '300100';  DRCR = 'C';
       AMTCTS = 55000;  DESCR = 'ACCRUAL RELIEF';
       WRITE TESTFL216;
       RECTYP = 'H';  BATNO = 'B00300';
       ACCTNO = '';  DRCR = ' ';
       AMTCTS = 0;  DESCR = 'ZERO CONTROL BATCH';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00300';
       ACCTNO = '500100';  DRCR = 'D';
       AMTCTS = 12500;  DESCR = 'SUSPENSE';
       WRITE TESTFL216;
       RECTYP = 'D';  BATNO = 'B00300';
       ACCTNO = '300100';  DRCR = 'C';
       AMTCTS = 12500;  DESCR = 'SUSPENSE OFFSET';
       WRITE TESTFL216;
      /end-free
     C*-----------------------------------------------------------------
     C* MAIN LINE
     C*-----------------------------------------------------------------
     C                   EXSR      INZSR1
     C                   READ      TESTFL216
     C                   DOW       NOT %EOF(TESTFL216)
     C* 01 = BATCH HEADER, 02 = JOURNAL DETAIL
     C   01              EXSR      HDRSR
     C   02              EXSR      DTLSR
     C                   READ      TESTFL216
     C                   ENDDO
     C* EDIT THE LAST BATCH, THEN PRINT THE RUN SUMMARY
     C                   EXSR      EDTSR
     C                   EXSR      SUMSR
     C                   RETURN
     O* ONE PHYSICAL LAYOUT SERVES BOTH RECORD TYPES
     OTESTFL216
     O                       RECTYP               1
     O                       BATNO                7
     O                       ACCTNO              13
     O                       DRCR                14
     O                       AMTCTS              25
     O                       DESCR               48
     C*-----------------------------------------------------------------
     C* INZSR1  -  CLEAR ACCUMULATORS AND NAME THE ACCOUNT CLASSES
     C*-----------------------------------------------------------------
     C     INZSR1        BEGSR
     C                   EVAL      CLSNAM(1) = 'BALANCE SHEET'
     C                   EVAL      CLSNAM(2) = 'EXPENSE'
     C                   EVAL      CLSNAM(3) = 'UNCLASSIFIED'
     C                   FOR       IX = 1 TO 3
     C                   Z-ADD     0             CLSTOT(IX)
     C                   ENDFOR
     C                   Z-ADD     0             DRTOT
     C                   Z-ADD     0             CRTOT
     C                   Z-ADD     0             BATCNT
     C                   Z-ADD     0             LINCNT
     C                   Z-ADD     0             ERRCNT
     C                   EVAL      CURBAT = *BLANKS
     C* 50 SUPPRESSES THE EDIT ON THE FIRST HEADER, WHEN NO BATCH IS OPEN
     C                   EVAL      *IN50 = *ON
     C                   EVAL      RPTLIN = 'GL POSTING REGISTER'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C     OKSR          BEGSR
     C                   EVAL      RPTLIN = '  BATCH BALANCED - POSTED'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C* DEBITS DO NOT EQUAL CREDITS
     C     BALERR        BEGSR
     C                   ADD       1             ERRCNT
     C                   Z-ADD     DRTOT         WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = '  ** OUT OF BALANCE  DR ' +
     C                             %EDITC(WRKDLR:'1')
     C     RPTLIN        DSPLY
     C                   Z-ADD     CRTOT         WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = '                     CR ' +
     C                             %EDITC(WRKDLR:'1')
     C     RPTLIN        DSPLY
     C                   ENDSR
     C* THE BATCH BALANCES BUT DISAGREES WITH ITS HEADER CONTROL TOTAL
     C     CTLERR        BEGSR
     C                   ADD       1             ERRCNT
     C                   Z-ADD     SAVEXP        WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = '  ** CONTROL TOTAL SAYS ' +
     C                             %EDITC(WRKDLR:'1')
     C     RPTLIN        DSPLY
     C                   Z-ADD     DRTOT         WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = '     BATCH POSTS         ' +
     C                             %EDITC(WRKDLR:'1')
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* EDTSR   -  BALANCE THE OPEN BATCH AGAINST ITS CONTROL TOTAL
     C*-----------------------------------------------------------------
     C     EDTSR         BEGSR
     C* DEBITS MUST EQUAL CREDITS
     C     DRTOT         COMP      CRTOT                                  60
     C* AND THE DEBIT SIDE MUST MATCH THE HEADER CONTROL TOTAL
     C     DRTOT         COMP      SAVEXP                                 61
     C* BOTH CONDITIONS TOGETHER MEAN THE BATCH POSTS CLEAN
     C   60
     CAN 61              EXSR      OKSR
     C  N60              EXSR      BALERR
     C   60
     CANN61              EXSR      CTLERR
     C* VARIANCE AGAINST THE CONTROL TOTAL, AS A PERCENTAGE.  A BATCH
     C* WITH A ZERO CONTROL TOTAL HAS NO PERCENTAGE TO REPORT.
     C                   MONITOR
     C     DRTOT         SUB       SAVEXP        VARNCE
     C     SAVEXP        COMP      0                                      62
     C                   IF        *IN62
     C                   EVAL      RPTLIN = '  VARIANCE PCT N/A'
     C                   ELSE
     C                   EVAL      VARPCT = VARNCE * 100 / SAVEXP
     C                   EVAL      RPTLIN = '  VARIANCE PCT ' +
     C                             %EDITC(VARPCT:'1')
     C                   ENDIF
     C     RPTLIN        DSPLY
     C                   ON-ERROR
     C                   EVAL      RPTLIN = '  VARIANCE PCT NOT COMPUTED'
     C     RPTLIN        DSPLY
     C                   ENDMON
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* HDRSR   -  A NEW BATCH HEADER CLOSES OUT THE PREVIOUS BATCH
     C*-----------------------------------------------------------------
     C     HDRSR         BEGSR
     C  N50              EXSR      EDTSR
     C                   EVAL      *IN50 = *OFF
     C                   EVAL      CURBAT = BATNO
     C* HOLD THIS BATCH'S CONTROL TOTAL - THE NEXT HEADER READ WILL
     C* OVERWRITE EXPTOT BEFORE THIS BATCH IS EDITED
     C                   Z-ADD     EXPTOT        SAVEXP
     C                   Z-ADD     0             DRTOT
     C                   Z-ADD     0             CRTOT
     C                   ADD       1             BATCNT
     C                   EVAL      RPTLIN = 'BATCH ' + CURBAT + ' ' +
     C                             %TRIM(DESCR)
     C     RPTLIN        DSPLY
     C                   ENDSR
     C* ACCOUNT CLASS ROUTINES REACHED FROM THE CASEQ CHAIN ABOVE
     C     BALSR         BEGSR
     C                   Z-ADD     1             CLSIX
     C                   ENDSR
     C     EXPSR         BEGSR
     C                   Z-ADD     2             CLSIX
     C                   ENDSR
     C     OTHSR         BEGSR
     C                   Z-ADD     3             CLSIX
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* DTLSR   -  ACCUMULATE ONE JOURNAL LINE
     C*-----------------------------------------------------------------
     C     DTLSR         BEGSR
     C                   ADD       1             LINCNT
     C* A DETAIL LINE BELONGING TO NO OPEN BATCH IS AN ORPHAN
     C     BATNO         COMP      CURBAT                                 51
     C  N51              GOTO      DTLEND
     C* CLASSIFY BY THE LEADING DIGIT OF THE ACCOUNT NUMBER
     C                   EVAL      ACCT1 = %SUBST(ACCTNO:1:1)
     C     ACCT1         CASEQ     '3'           BALSR
     C     ACCT1         CASEQ     '4'           EXPSR
     C                   CAS                     OTHSR
     C                   ENDCS
     C                   ADD       AMTCTS        CLSTOT(CLSIX)
     C* DEBITS AND CREDITS ACCUMULATE SEPARATELY FOR THE BALANCE EDIT
     C     DRCR          COMP      'D'                                    52
     C   52              ADD       AMTCTS        DRTOT
     C  N52              ADD       AMTCTS        CRTOT
     C                   Z-ADD     AMTCTS        WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = '  ' + ACCTNO + ' ' + DRCR + ' ' +
     C                             %EDITC(WRKDLR:'1') + ' ' + %TRIM(DESCR)
     C     RPTLIN        DSPLY
     C     DTLEND        TAG
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* SUMSR   -  RUN SUMMARY
     C*-----------------------------------------------------------------
     C     SUMSR         BEGSR
     C                   EVAL      RPTLIN = '---- RUN SUMMARY ----'
     C     RPTLIN        DSPLY
     C                   FOR       IX = 1 TO 3
     C                   Z-ADD     CLSTOT(IX)    WRKNUM
     C                   EVAL      WRKDLR = WRKNUM / 100
     C                   EVAL      RPTLIN = CLSNAM(IX) + ' ' +
     C                             %EDITC(WRKDLR:'1')
     C     RPTLIN        DSPLY
     C                   ENDFOR
     C                   EVAL      RPTLIN = 'BATCHES ' + %CHAR(BATCNT) +
     C                             '  LINES ' + %CHAR(LINCNT) + '  IN ERROR ' +
     C                             %CHAR(ERRCNT)
     C     RPTLIN        DSPLY
     C                   ENDSR
