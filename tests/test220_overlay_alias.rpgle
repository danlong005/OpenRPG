     HDFTACTGRP(*NO)
     D*REGRESSION: OVERLAY MUST SHARE STORAGE WITH THE FIELD IT
     D*OVERLAYS.  WRITING EITHER THE BASE OR A SUBFIELD HAS TO BE
     D*VISIBLE THROUGH THE OTHER -- SUBFIELDS ARE NOT COPIES.
     DPART             DS                  QUALIFIED
     DKEY                            12A
     DITEM                            6A   OVERLAY(KEY)
     DQTY                             5S 2 OVERLAY(KEY:7)

     DSHOW             S              7S 2
      /free
       // base assigned first: the subfields must read slices of it
       part.key = 'ABC123001234';
       DSPLY ('item=[' + part.item + ']');
       DSPLY ('seg2=[' + %SUBST(part.key:7:5) + ']');
       
       // writing a character subfield must change the base
       part.item = 'XYZ789';
       DSPLY ('key=[' + part.key + ']');
       
       // writing a numeric subfield must change the base too, as digits
       part.qty = 56.78;
       DSPLY ('key=[' + part.key + ']');
       
       // and reading it back through the overlay must recover the value
       show = part.qty;
       DSPLY ('qty=' + %EDITC(show:'1'));
       
       // a change to the base is seen by the numeric overlay as well
       part.key = 'PQR000009900';
       show = part.qty;
       DSPLY ('item=[' + part.item + '] qty=' + %EDITC(show:'1'));
       *INLR = *ON;
      /end-free
