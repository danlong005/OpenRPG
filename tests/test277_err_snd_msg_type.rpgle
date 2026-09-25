**FREE
// SND-MSG takes the message type directly: SND-MSG *INFO 'text'. IBM i
// reads TYPE(*INFO) as a variable named TYPE (RNF0203, RNF7030).
SND-MSG TYPE(*INFO) 'Processing complete';
*INLR = *ON;
