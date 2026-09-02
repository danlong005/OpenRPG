     H*-----------------------------------------------------------------
     H* INVREO  -  INVENTORY REORDER ANALYSIS
     H*-----------------------------------------------------------------
     H* WALKS THE ITEM TABLE, CLASSIFIES EACH ITEM'S STOCK POSITION AND
     H* RAISES A SUGGESTED PURCHASE ORDER FOR ANYTHING AT OR BELOW ITS
     H* REORDER POINT.  AVAILABLE = ON HAND PLUS ON ORDER.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
      /COPY tests/copybook217_item.rpgle
     D* ITEM TABLE - LOADED BY THE INITIALISATION ROUTINE
     DITEM             S              4A   DIM(6)
     DIDESC            S             16A   DIM(6)
     DONHND            S              7P 0 DIM(6)
     DONORD            S              7P 0 DIM(6)
     DRORDP            S              7P 0 DIM(6)
     DEOQ              S              7P 0 DIM(6)
     DVEND             S              3A   DIM(6)
     D* VENDOR CODES ACTUALLY ORDERED FROM, SORTED FOR THE TRAILER
     DVLIST            S              3A   DIM(6)
     DVCOUNT           S              5P 0
     D* WORK FIELDS
     DIX               S              5P 0
     DJX               S              5P 0
     DSTSIX            S              5P 0
     DAVAIL            S              7P 0
     DSHORT            S              7P 0
     DORDQTY           S              7P 0
     DTOTORD           S              9P 0
     DLINES            S              5P 0
     DWRKNUM           S              9P 0
     DWRKITM           S              4A
     DWRKDSC           S             16A
     DWRKVND           S              3A
     DRPTLIN           S             70A
     C*-----------------------------------------------------------------
     C* MAIN LINE
     C*-----------------------------------------------------------------
     C                   EXSR      INZSR1
     C                   FOR       IX = 1 TO 6
     C                   EXSR      ITMSR
     C                   ENDFOR
     C                   EXSR      TRLSR
     C                   RETURN
     C*-----------------------------------------------------------------
     C* INZSR1  -  LOAD THE ITEM TABLE AND CLEAR THE ACCUMULATORS
     C*-----------------------------------------------------------------
     C     INZSR1        BEGSR
     C                   EVAL      STSNAM(1) = 'STOCKOUT'
     C                   EVAL      STSNAM(2) = 'REORDER'
     C                   EVAL      STSNAM(3) = 'WATCH'
     C                   EVAL      STSNAM(4) = 'OK'
     C                   FOR       JX = 1 TO 4
     C                   Z-ADD     0             STSCNT(JX)
     C                   ENDFOR
     C                   EVAL      ITEM(1) = 'A100'
     C                   EVAL      IDESC(1) = 'HEX BOLT 1/4'
     C                   Z-ADD     120           ONHND(1)
     C                   Z-ADD     0             ONORD(1)
     C                   Z-ADD     200           RORDP(1)
     C                   Z-ADD     500           EOQ(1)
     C                   EVAL      VEND(1) = 'V01'
     C                   EVAL      ITEM(2) = 'A200'
     C                   EVAL      IDESC(2) = 'HEX NUT 1/4'
     C                   Z-ADD     850           ONHND(2)
     C                   Z-ADD     0             ONORD(2)
     C                   Z-ADD     300           RORDP(2)
     C                   Z-ADD     500           EOQ(2)
     C                   EVAL      VEND(2) = 'V01'
     C                   EVAL      ITEM(3) = 'B100'
     C                   EVAL      IDESC(3) = 'WASHER FLAT'
     C                   Z-ADD     40            ONHND(3)
     C                   Z-ADD     100           ONORD(3)
     C                   Z-ADD     150           RORDP(3)
     C                   Z-ADD     400           EOQ(3)
     C                   EVAL      VEND(3) = 'V02'
     C                   EVAL      ITEM(4) = 'B200'
     C                   EVAL      IDESC(4) = 'COTTER PIN'
     C                   Z-ADD     0             ONHND(4)
     C                   Z-ADD     0             ONORD(4)
     C                   Z-ADD     75            RORDP(4)
     C                   Z-ADD     250           EOQ(4)
     C                   EVAL      VEND(4) = 'V02'
     C                   EVAL      ITEM(5) = 'C100'
     C                   EVAL      IDESC(5) = 'GREASE FITTING'
     C                   Z-ADD     150           ONHND(5)
     C                   Z-ADD     0             ONORD(5)
     C                   Z-ADD     100           RORDP(5)
     C                   Z-ADD     200           EOQ(5)
     C                   EVAL      VEND(5) = 'V03'
     C                   EVAL      ITEM(6) = 'C200'
     C                   EVAL      IDESC(6) = 'SET SCREW M6'
     C                   Z-ADD     60            ONHND(6)
     C                   Z-ADD     20            ONORD(6)
     C                   Z-ADD     100           RORDP(6)
     C                   Z-ADD     300           EOQ(6)
     C                   EVAL      VEND(6) = 'V03'
     C                   Z-ADD     0             TOTORD
     C                   Z-ADD     0             LINES
     C                   Z-ADD     0             VCOUNT
     C                   FOR       JX = 1 TO 6
     C                   EVAL      VLIST(JX) = 'ZZZ'
     C                   ENDFOR
     C                   EVAL      RPTLIN = 'INVENTORY REORDER ANALYSIS'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C* STOCK STATUS ROUTINES REACHED FROM THE CASEQ CHAIN IN ITMSR
     C     OUTSR         BEGSR
     C                   Z-ADD     1             STSIX
     C                   ENDSR
     C     REOSR         BEGSR
     C                   Z-ADD     2             STSIX
     C                   ENDSR
     C     WCHSR         BEGSR
     C                   Z-ADD     3             STSIX
     C                   ENDSR
     C     OKSR          BEGSR
     C                   Z-ADD     4             STSIX
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* VNDSR   -  REMEMBER A VENDOR THE RUN HAS RAISED AN ORDER ON
     C*-----------------------------------------------------------------
     C     VNDSR         BEGSR
     C                   EVAL      JX = %LOOKUP(WRKVND:VLIST)
     C                   IF        JX = 0
     C                   ADD       1             VCOUNT
     C                   EVAL      VLIST(VCOUNT) = WRKVND
     C                   ENDIF
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* ITMSR   -  ANALYSE ONE ITEM
     C*-----------------------------------------------------------------
     C     ITMSR         BEGSR
     C                   EVAL      WRKITM = ITEM(IX)
     C                   EVAL      WRKDSC = IDESC(IX)
     C                   EVAL      WRKVND = VEND(IX)
     C* BUILD THE TEN BYTE PART KEY THE PURCHASING SYSTEM EXPECTS:
     C* THE ITEM CODE LEFT ADJUSTED, THE VENDOR CODE RIGHT ADJUSTED
     C                   MOVEL     WRKITM        PARTKY
     C                   MOVE      WRKVND        PARTKY
     C* THE LEADING LETTER IS THE STOCK CLASS
     C                   EVAL      PRTCLS = %SUBST(PARTKY:1:1)
     C* AVAILABLE = ON HAND + ON ORDER
     C     ONHND(IX)     ADD       ONORD(IX)     AVAIL
     C* CLASSIFY THE STOCK POSITION
     C     AVAIL         COMP      0                                      30
     C     AVAIL         COMP      RORDP(IX)                          31
     C                   IF        *IN30
     C                   EXSR      OUTSR
     C                   ELSEIF    NOT *IN31
     C                   EXSR      REOSR
     C                   ELSEIF    AVAIL < RORDP(IX) * 2
     C                   EXSR      WCHSR
     C                   ELSE
     C                   EXSR      OKSR
     C                   ENDIF
     C                   ADD       1             STSCNT(STSIX)
     C* RAISE A SUGGESTED ORDER FOR ANYTHING AT OR BELOW ITS POINT
     C                   Z-ADD     0             ORDQTY
     C                   IF        STSIX <= 2
     C     RORDP(IX)     SUB       AVAIL         SHORT
     C                   Z-ADD     EOQ(IX)       ORDQTY
     C* A SHORTFALL BIGGER THAN THE ECONOMIC ORDER QUANTITY GETS
     C* ROUNDED UP TO COVER IT
     C                   IF        SHORT > ORDQTY
     C                   Z-ADD     SHORT         ORDQTY
     C                   ENDIF
     C                   ADD       ORDQTY        TOTORD
     C                   ADD       1             LINES
     C                   EXSR      VNDSR
     C                   ENDIF
     C* DETAIL LINE
     C                   Z-ADD     ONHND(IX)     WRKNUM
     C                   EVAL      RPTLIN = PARTKY + ' ' + PRTCLS + ' ' +
     C                             WRKDSC + ' OH ' + %CHAR(WRKNUM)
     C                   Z-ADD     AVAIL         WRKNUM
     C                   EVAL      RPTLIN = %TRIM(RPTLIN) + ' AV ' +
     C                             %CHAR(WRKNUM)
     C                   Z-ADD     ORDQTY        WRKNUM
     C                   EVAL      RPTLIN = %TRIM(RPTLIN) + ' ORD ' +
     C                             %CHAR(WRKNUM) + ' ' + %TRIM(STSNAM(STSIX))
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* TRLSR   -  RUN TRAILER
     C*-----------------------------------------------------------------
     C     TRLSR         BEGSR
     C                   EVAL      RPTLIN = '---- SUMMARY ----'
     C     RPTLIN        DSPLY
     C                   FOR       JX = 1 TO 4
     C                   Z-ADD     STSCNT(JX)    WRKNUM
     C                   EVAL      RPTLIN = STSNAM(JX) + ' ' + %CHAR(WRKNUM)
     C     RPTLIN        DSPLY
     C                   ENDFOR
     C                   Z-ADD     LINES         WRKNUM
     C                   EVAL      RPTLIN = 'ORDER LINES ' + %CHAR(WRKNUM)
     C     RPTLIN        DSPLY
     C                   Z-ADD     TOTORD        WRKNUM
     C                   EVAL      RPTLIN = 'TOTAL UNITS ' + %CHAR(WRKNUM)
     C     RPTLIN        DSPLY
     C* VENDORS ON THIS RUN, IN CODE ORDER
     C                   SORTA     VLIST
     C                   EVAL      RPTLIN = 'VENDORS'
     C                   FOR       JX = 1 TO VCOUNT
     C                   EVAL      RPTLIN = %TRIM(RPTLIN) + ' ' + VLIST(JX)
     C                   ENDFOR
     C     RPTLIN        DSPLY
     C                   ENDSR
