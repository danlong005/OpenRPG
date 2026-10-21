**FREE
// LIKE(ds.name) where the data structure has no such subfield (RNF7030).
dcl-ds outer qualified;
  code char(4);
end-ds;
dcl-s c like(outer.nosuch);
*inlr = *on;
