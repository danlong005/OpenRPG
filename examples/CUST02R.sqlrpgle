**free

// CUST02R — Collect email addresses and mark messages as sent
//
// Reads:   messages  (cursor — pending messages where status = ' ')
//          customers (singleton select — fetch email and name by id)
// Updates: messages  (set email and status = 'X')

dcl-s msgId  packed(10:0);
dcl-s custId packed(10:0);
dcl-s email  varchar(100);
dcl-s fname  varchar(50);
dcl-s dspLine varchar(52);   // dsply shows at most 52 characters

exec sql declare c1 cursor for
  select id, customer_id
  from   messages
  where  status = ' ';

exec sql open c1;
exec sql fetch next from c1 into :msgId, :custId;

dow sqlstate < '02000';

  exec sql select email, first_name
           into   :email, :fname
           from   customers
           where  id = :custId;

  exec sql update messages
           set    email  = :email,
                  status = 'X'
           where  id = :msgId;

  dspLine = 'Email queued for ' + %trim(fname) + ': ' + %trim(email);
  dsply dspLine;

  exec sql fetch next from c1 into :msgId, :custId;
enddo;

exec sql close c1;

*inlr = *on;
