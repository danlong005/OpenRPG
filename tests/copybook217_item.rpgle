     D*----------------------------------------------------------------
     D* ITEM MASTER WORK DEFINITIONS - COPIED BY THE REORDER PROGRAMS
     D*----------------------------------------------------------------
     D* THE ITEM KEY IS A CLASS LETTER FOLLOWED BY A THREE DIGIT
     D* SEQUENCE, CARRIED AROUND AS ONE TEN BYTE FIELD.
     DPARTKY           S             10A
     DPRTCLS           S              1A
     D* STOCK STATUS CODES SHARED BY EVERY PROGRAM IN THE APPLICATION
     DSTSNAM           S             10A   DIM(4)
     DSTSCNT           S              5P 0 DIM(4)
