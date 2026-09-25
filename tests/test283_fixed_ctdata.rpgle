     H*TEST 283: FIXED-FORMAT COMPILE-TIME DATA. BARE ** SECTIONS LOAD THE
     H*CTDATA ARRAYS IN THE ORDER THEY ARE DECLARED.
     DCODES            S              2A   DIM(4) CTDATA PERRCD(2)
     DQTYS             S              3S 0 DIM(3) CTDATA
     DI                S             10I 0
     C     CODES(1)      DSPLY
     C     CODES(4)      DSPLY
     C                   EVAL      I = QTYS(1) + QTYS(2) + QTYS(3)
     C     I             DSPLY
     C                   EVAL      *INLR = *ON
**
AABB
CCDD
**
005
010
100
