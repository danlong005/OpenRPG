**FREE
// A DIM subfield of a data structure without QUALIFIED is written bare:
// arr(i) as a value and a target, and CLEAR arr for every element.
dcl-ds d;
  arr char(2) dim(3);
end-ds;
arr(2) = 'AB';
if arr(2) = 'AB';
  dsply arr(2);
endif;
clear arr;
dsply ('[' + arr(2) + '] ' + %char(%elem(arr)));
*inlr = *on;
