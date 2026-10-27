      * An array of LIKEDS subfields on a fixed-format D-spec, and %SIZE of
      * the data structure: 4 + 3 x (10 + 3) bytes.
     D line_t          DS                  qualified template
     D  item                         10A
     D  qty                           5P 0
     D order           DS                  qualified
     D  id                           10I 0
     D  lines                              likeds(line_t) dim(3)
     C                   EVAL      order.lines(3).item = 'Z'
     C                   EVAL      order.lines(3).qty = 7
     C                   EVAL      order.id = %size(order)
     C     order.id      DSPLY
     C                   EVAL      *INLR = *ON
