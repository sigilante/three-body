|%
::
+$  cause
  $%  [%tx-sent tx-hash=@t]
      [%tx-fail error=@t]
      [%born ~]
  ==
::
+$  effect
  $%
    $:  %tx
        %send
        src-pkh=@
        src-privkey=@
        src-first-name=*
        trg-pkh=@
        amount=@
    ==
    [%exit ~]
  ==
::
--
