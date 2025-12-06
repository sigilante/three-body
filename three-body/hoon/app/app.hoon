::  three-body/app/three-body.hoon
::  Browser-based three-body problem served as a NockApp
::
/+  http, three-body, txt=types
/=  *  /common/wrapper
::  Wallet imports
/=  wallet        /apps/wallet/wallet
/=  wt            /apps/wallet/lib/types
::  Static resources (load as [@ud @t])
/*  index         %html   /app/site/index/html
/*  style         %css    /app/site/style/css
/*  game          %js     /app/site/game/js
::  Removed missing asset references (watcher, wallet, sprites)
::  Application state
=>
|%
+$  server-state
  $:  %0
      sessions=(map game-id:three-body session-state:three-body)
      config=(unit runtime-config:three-body)  :: Runtime config (poked from Rust)
  ==
::
::  Default server configuration (fallback if no config poked)
::
++  default-config
  ^-  runtime-config:three-body
  :*  wallet-pkh=%''
      private-key=~
      confirmation-blocks=3
      enable-blockchain=%.n
      initial-bank=1.000
      max-history-entries=20
      notes=*(map @t *)
  ==
::
::  Get config (either from state or default)
::
++  get-config
  |=  state=server-state
  ^-  runtime-config:three-body
  ?~  config.state
    default-config
  u.config.state
--
::  Application logic
=>
|%
++  moat  (keep server-state)
::
++  inner
  |_  state=server-state
  ::
  ::  +load: upgrade from previous state
  ::
  ++  load
    |=  arg=server-state
    ^-  server-state
    arg
  ::
  ::  +peek: external inspect
  ::
  ++  peek
    |=  =path
    ^-  (unit (unit *))
    ~>  %slog.[0 'Peeks awaiting implementation']
    ~
  ::
  ::  +poke: external apply
  ::
  ++  poke
    |=  =ovum:moat
    ^-  [(list ?(effect:http effect:wt effect:txt)) server-state]
    ::  Extract entropy from poke input
    =/  entropy=@  eny.input.ovum
    ::
    ::  Check if this is a config poke (non-HTTP)
    =/  config-poke=(unit config-poke:three-body)
      ((soft config-poke:three-body) cause.input.ovum)
    ?^  config-poke
      ::  Handle init-config poke
      ~&  >>  "Received init-config poke"
      =/  new-config=runtime-config:three-body
        :*  wallet-pkh.u.config-poke
            `private-key.u.config-poke
            confirmation-blocks.u.config-poke
            enable-blockchain.u.config-poke
            initial-bank.u.config-poke
            max-history.u.config-poke
            ~  :: empty notes map initially
        ==
      ~&  >>  "Config updated with PKH: {<wallet-pkh.new-config>}"
      [~ state(config `new-config)]
    ::
    ::  Check if this is a tx-driver response
    =/  tx-response=(unit tx-driver-cause:three-body)
      ((soft tx-driver-cause:three-body) cause.input.ovum)
    ?^  tx-response
      ::  Handle transaction driver response
      ~&  >>  "Received tx-driver response: {<u.tx-response>}"
      ?-    -.u.tx-response
          %born
        ~&  >>  "Transaction born event received"
        [~ state]
        ::
          %tx-sent
        ::  Transaction successfully sent
        ~&  >>  "Transaction sent with hash: {<tx-hash.u.tx-response>} for game: {<game-id.u.tx-response>}"
        ::  Update session state with tx-hash
        =/  game-id=game-id:three-body  game-id.u.tx-response
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found for tx-sent: {<game-id>}"
          [~ state]
        ::  Update session with tx-hash
        =/  updated-session=session-state:three-body
          u.existing(cashout-tx-hash `tx-hash.u.tx-response, last-activity now.input.ovum)
        ~&  >>  "Updated session {<game-id>} with tx-hash: {<tx-hash.u.tx-response>}"
        [~ state(sessions (~(put by sessions.state) game-id updated-session))]
      ::
          %tx-fail
        ::  Transaction failed
        ~&  >>>  "Transaction failed for game {<game-id.u.tx-response>}: {<error.u.tx-response>}"
        ::  TODO: Rollback bank deduction if needed
        ::  For now, just log the failure
        [~ state]
      ==
    ::
    ::  Check if this is a balance update from the Rust driver
    =/  update-bank-response=(unit update-bank-cause:three-body)
      ((soft update-bank-cause:three-body) cause.input.ovum)
    ?^  update-bank-response
      ::  Update the bank in all active sessions
      =/  new-bank=@ud  p.u.update-bank-response
      ~&  >>  "Received balance update: new bank = {<new-bank>}"
      ::  Update config with new bank
      =/  current-config=runtime-config:three-body  (get-config state)
      =/  updated-config=runtime-config:three-body
        current-config(initial-bank new-bank)
      [~ state(config `updated-config)]
    ::
    ::  Otherwise, parse as HTTP request
    =/  sof-cau=(unit cause:http)  ((soft cause:http) cause.input.ovum)
    ?~  sof-cau
      ~&  "cause incorrectly formatted!"
      ~&  now.input.ovum
      ~&  >  ovum
      !!
    ::  Parse request into components.
    =/  [id=@ uri=@t =method:http headers=(list header:http) body=(unit octs:http)]
      +.u.sof-cau
    ~&  >  "Received request: {<method>} {<uri>}"
    =/  uri=path  (pa:dejs:http [%s uri])
    ~&  >>  "Parsed path: {<uri>}"
    ~&  >>  "Method: {<method>}"
    ::  Handle GET/POST requests
    ?+    method  [~[[%res ~ %400 ~ ~]] state]
      ::
        %'GET'
      ?+    uri
        ~&  >>>  "No route matched, returning 404 for: {<uri>}"
        [~[[%res ~ %404 ~ ~]] state]
        ::
          :: Serve index.html at /three-body
          [%three-body ~]
        ~&  >>  "Matched route: /three-body (index.html)"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/html']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ['Pragma' 'no-cache']
                ['Expires' '0']
            ==
            (to-octs:http q.index)
        ==
        ::
          :: Serve style.css at /three-body/style.css
          [%three-body %'style.css' ~]
        ~&  >>  "Matched route: /three-body/style.css"
        ~&  >>  "CSS length: {<(met 3 q.style)>} bytes"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/css']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ['Pragma' 'no-cache']
                ['Expires' '0']
            ==
            (to-octs:http q.style)
        ==
        ::
          :: Serve game.js at /three-body/game.js
          [%three-body %'game.js' ~]
        ~&  >>  "Matched route: /three-body/game.js"
        ~&  >>  "JS length: {<(met 3 q.game)>} bytes"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/javascript']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ['Pragma' 'no-cache']
                ['Expires' '0']
            ==
            (to-octs:http q.game)
        ==
        ::
          :: Serve sprites.png at /three-body/img/sprites.png
          [%three-body %img %'sprites.png' ~]
        ~&  >>  "Matched route: /three-body/img/sprites.png"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'image/png']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ['Pragma' 'no-cache']
                ['Expires' '0']
            ==
            (to-octs:http q.sprites)
        ==
        ::
          :: Serve watcher.html
          [%three-body %'watcher.html' ~]
        ~&  >>  "Matched route: /three-body/watcher.html"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/html']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.watcher-html)
        ==
        ::
          :: Serve watcher.js
          [%three-body %'watcher.js' ~]
        ~&  >>  "Matched route: /three-body/watcher.js"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/javascript']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.watcher-js)
        ==
        ::
          :: Serve watcher.css
          [%three-body %'watcher.css' ~]
        ~&  >>  "Matched route: /three-body/watcher.css"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/css']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.watcher-css)
        ==
        ::
          :: Serve wallet.html
          [%three-body %'wallet.html' ~]
        ~&  >>  "Matched route: /three-body/wallet.html"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/html']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.wallet-html)
        ==
        ::
          :: Serve wallet.js
          [%three-body %'wallet.js' ~]
        ~&  >>  "Matched route: /three-body/wallet.js"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/javascript']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.wallet-js)
        ==
        ::
          :: Serve wallet.css
          [%three-body %'wallet.css' ~]
        ~&  >>  "Matched route: /three-body/wallet.css"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'text/css']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http q.wallet-css)
        ==
        ::
          :: GET /api/sessions - List all active sessions
          [%three-body %api %sessions ~]
        ~&  >>  "Matched route: GET /three-body/api/sessions"
        ~&  >>>  "Total sessions in state: {<~(wyt by sessions.state)>}"
        ::  Extract session info from all sessions
        ~&  >  sessions+[~(tap by sessions.state)]
        =/  session-list=(list [game-id=@t status=session-status:three-body bank=@ud deals-made=@ud])
          %+  turn  ~(tap by sessions.state)
          |=  [gid=@t sess=session-state:three-body]
          ^-  [game-id=@t status=session-status:three-body bank=@ud deals-made=@ud]
          [gid status.sess bank.game.sess deals-made.game.sess]
        ~&  >>>  "Session list length: {<(lent session-list)>}"
        =/  json=tape
          (make-json-sessions-list:three-body session-list)
        ~&  >>>  "JSON response: {<json>}"
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          :: GET /api/{game-id}/status - Get full session state
          [%three-body %api game-id:three-body %status ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched route: GET /three-body/api/{<game-id>}/status"
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          :_  ~
          ^-  effect:http
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  json=tape
          (make-json-full-session:three-body u.existing)
        :_  state
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
      ==  :: end GET
      ::
        %'POST'
      ~&  >>  "POST request detected!"
      ?+    uri
        ~&  >>  "No POST route matched for: {<uri>}"
        [~[[%res ~ %500 ~ ~]] state]
        ::
          :: Create new game session
          [%three-body %api %session %create ~]
        ~&  >>  "Matched /three-body/api/session/create route"
        ::  Generate UUID from entropy
        =/  =game-id:three-body  (generate-uuid:three-body entropy)
        ~&  >>  "Generated game-id: {<game-id>}"
        ::  Create initial game state
        =/  config=runtime-config:three-body  (get-config state)
        =/  initial-game=game-state-inner:three-body
          (initial-game-state:three-body initial-bank.config)
        ::  Create session state
        =/  new-session=session-state:three-body
          :*  game-id=game-id
              player-pkh=~
              bet-tx-hash=~
              bet-status=%pending
              confirmed-amount=0
              cashout-tx-hash=~
              game=initial-game
              created=now.input.ovum
              last-activity=now.input.ovum
              status=%awaiting-bet
              history=~
          ==
        ::  Return session info with server PKH and initial bank
        =/  json=tape
          (make-json-session-created:three-body game-id wallet-pkh.config bank.initial-game)
        ~&  >>  "Created session: {<game-id>}"
        :_  state(sessions (~(put by sessions.state) game-id new-session))
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Deal initial hands
          [%three-body %api game-id:three-body %deal ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/deal route"
        ::  Parse body to get bet amount
        ?~  body
          =/  error-json=tape  (make-json-error:three-body 400 "Missing request body")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  body-text=tape  (trip q.u.body)
        =/  bet-parsed=(unit @ud)  (parse-json-number:three-body "bet" body-text)
        =/  bet=@ud  ?~(bet-parsed 100 u.bet-parsed)
        ~&  >>  "Using bet: {<bet>}"
        ::
        ::  Get session state
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate game action
        =/  validation-error=(unit tape)
          (validate-game-action:three-body %deal current-session)
        ?^  validation-error
          =/  error-json=tape  (make-json-error:three-body 400 u.validation-error)
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Check if player can afford the bet
        ?:  (gth bet bank.current-game)
          =/  error-json=tape  (make-json-error:three-body 400 "Insufficient funds")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Deduct bet from bank
        =/  new-bank=@ud  (sub bank.current-game bet)
        ::
        ::  Create and shuffle deck with entropy
        =/  fresh-deck=(list card:three-body)  create-deck:three-body
        =/  shuffled-deck=(list card:three-body)
          (shuffle-deck:three-body fresh-deck `@uvJ`entropy)
        ::
        ::  Deal initial hands
        =+  [player-hand dealer-hand remaining-deck]=(deal-initial:three-body shuffled-deck)
        =/  player-score=@ud  (hand-value:three-body (snag 0 player-hand))
        =/  dealer-visible=card:three-body  (snag 1 (snag 0 dealer-hand))
        ::
        ::  Update game state with bet deducted
        =/  updated-game=game-state-inner:three-body
          current-game(deck remaining-deck, player-hand player-hand, dealer-hand dealer-hand, current-bet bet, bank new-bank, game-in-progress %.y, dealer-turn %.n, deals-made +(deals-made.current-game))
        ::
        ::  Update session state (set status to active)
        =/  updated-session=session-state:three-body
          current-session(game updated-game, last-activity now.input.ovum, status %active)
        ~&  >>  "Updated game - current-bet: {<current-bet.updated-game>}, bank: {<bank.updated-game>}"
        ::
        ::  Build response (note: using 0 for backward compat with old sessionId field)
        =/  json=tape
          (make-json-deal:three-body player-hand dealer-hand player-score dealer-visible 0 new-bank win-loss.updated-game)
        ::
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Player hits
          [%three-body %api game-id:three-body %hit ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/hit route"
        ::  Get session state
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate game action
        =/  validation-error=(unit tape)
          (validate-game-action:three-body %hit current-session)
        ?^  validation-error
          =/  error-json=tape  (make-json-error:three-body 400 u.validation-error)
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Draw card
        =+  [new-card remaining-deck]=(draw-card:three-body deck.current-game)
        =/  new-player-hand=hand:three-body  (snoc (snag 0 player-hand.current-game) new-card)
        =/  new-score=@ud  (hand-value:three-body new-player-hand)
        =/  busted=?  (is-busted:three-body new-player-hand)
        ::
        ::  Update game (end game if busted, clear bet and update win-loss)
        =/  updated-game=game-state-inner:three-body
          ?:  busted
            ::  Calculate loss for busting (payout=0, so profit = 0 - bet = -bet)
            =/  profit=@sd  (dif:si (sun:si 0) (sun:si current-bet.current-game))
            =/  new-win-loss=@sd  (sum:si win-loss.current-game profit)
            current-game(deck remaining-deck, player-hand (snap player-hand.current-game 0 new-player-hand), current-bet 0, win-loss new-win-loss, game-in-progress %.n)
          current-game(deck remaining-deck, player-hand (snap player-hand.current-game 0 new-player-hand))
        ::
        ::  Update session state
        =/  updated-session=session-state:three-body
          current-session(game updated-game, last-activity now.input.ovum, status ?:(busted %ended %active))
        ::
        =/  json=tape
          (make-json-hit:three-body new-card new-player-hand new-score busted bank.updated-game win-loss.updated-game)
        ::
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Player stands
          [%three-body %api game-id:three-body %stand ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/stand route"
        ::  Get session state
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate game action
        =/  validation-error=(unit tape)
          (validate-game-action:three-body %stand current-session)
        ?^  validation-error
          =/  error-json=tape  (make-json-error:three-body 400 u.validation-error)
          :_  state
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Dealer plays
        =/  final-dealer-hand=hand:three-body  (snag 0 dealer-hand.current-game)
        =/  remaining-deck=(list card:three-body)  deck.current-game
        |-
        ?:  (dealer-should-hit:three-body final-dealer-hand)
          =+  [new-card new-deck]=(draw-card:three-body remaining-deck)
          $(final-dealer-hand (snoc final-dealer-hand new-card), remaining-deck new-deck)
        ::
        ::  Resolve outcome
        ~&  >  "Stand - current-bet: {<current-bet.current-game>}, bank: {<bank.current-game>}"
        =+  [outcome multiplier]=(resolve-outcome:three-body (snag 0 player-hand.current-game) final-dealer-hand)
        ~&  >  "Outcome: {<outcome>}, multiplier: {<multiplier>}"
        =/  payout=@ud  (mul current-bet.current-game multiplier)
        ~&  >  "Payout: {<payout>}"
        =/  new-bank=@ud  (add bank.current-game payout)
        ~&  >  "New bank: {<new-bank>}"
        =/  dealer-score=@ud  (hand-value:three-body final-dealer-hand)
        ~&  >  "Win/loss: {<win-loss.current-game>}"
        ::
        ::  Calculate win/loss change (payout includes return of bet)
        =/  profit=@sd  (dif:si (sun:si payout) (sun:si current-bet.current-game))
        =/  new-win-loss=@sd  (sum:si win-loss.current-game profit)
        ::
        ::  Update game (clear bet when ending)
        =/  updated-game=game-state-inner:three-body
          current-game(dealer-hand (snap dealer-hand.current-game 0 final-dealer-hand), deck remaining-deck, bank new-bank, win-loss new-win-loss, current-bet 0, game-in-progress %.n)
        ::
        ::  Create history entry
        =/  history-entry=hand-history:three-body
          :*  bet=current-bet.current-game
              player-hand=(snag 0 player-hand.current-game)
              dealer-hand=final-dealer-hand
              outcome=outcome
              payout=payout
              bank-after=new-bank
              timestamp=now.input.ovum
          ==
        ::  Append to history (keep last N hands per config)
        =/  config=runtime-config:three-body  (get-config state)
        =/  new-history=(list hand-history:three-body)
          (append-to-history:three-body history-entry history.current-session max-history-entries.config)
        ::
        ::  Update session state (set status to ended and add history)
        =/  updated-session=session-state:three-body
          current-session(game updated-game, last-activity now.input.ovum, status %ended, history new-history)
        ::
        =/  json=tape
          (make-json-stand:three-body final-dealer-hand dealer-score outcome payout new-bank new-win-loss)
        ::
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Player doubles down
          [%three-body %api game-id:three-body %double ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/double route"
        ::  Get session state
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate game action
        =/  validation-error=(unit tape)
          (validate-game-action:three-body %double current-session)
        ?^  validation-error
          =/  error-json=tape  (make-json-error:three-body 400 u.validation-error)
          :_  state
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Check if player can afford to double
        ?:  (gth current-bet.current-game bank.current-game)
          =/  error-json=tape  (make-json-error:three-body 400 "Insufficient funds to double down")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Deduct additional bet from bank and double current-bet
        =/  new-bank=@ud  (sub bank.current-game current-bet.current-game)
        =/  doubled-bet=@ud  (mul current-bet.current-game 2)
        ::
        ::  Draw exactly one card
        =+  [new-card remaining-deck]=(draw-card:three-body deck.current-game)
        =/  new-player-hand=hand:three-body  (snoc (snag 0 player-hand.current-game) new-card)
        =/  player-busted=?  (is-busted:three-body new-player-hand)
        ::
        ::  If busted, game over (no need to play dealer hand)
        ?:  player-busted
          =/  dealer-hand-current=hand:three-body  (snag 0 dealer-hand.current-game)
          =/  dealer-score=@ud  (hand-value:three-body dealer-hand-current)
          ::  Calculate win/loss (busted = loss of doubled bet)
          =/  loss=@sd  (new:si %.n doubled-bet)
          =/  new-win-loss=@sd  (sum:si win-loss.current-game loss)
          =/  final-game=game-state-inner:three-body
            current-game(deck remaining-deck, player-hand (snap player-hand.current-game 0 new-player-hand), current-bet 0, bank new-bank, win-loss new-win-loss, game-in-progress %.n)
          ::  Create history entry (busted = loss)
          =/  history-entry=hand-history:three-body
            :*  bet=doubled-bet
                player-hand=new-player-hand
                dealer-hand=dealer-hand-current
                outcome=%loss
                payout=0
                bank-after=new-bank
                timestamp=now.input.ovum
            ==
          ::  Append to history (keep last N hands per config)
          =/  config=runtime-config:three-body  (get-config state)
          =/  new-history=(list hand-history:three-body)
            (append-to-history:three-body history-entry history.current-session max-history-entries.config)
          ::  Update session state (set status to ended and add history)
          =/  final-session=session-state:three-body
            current-session(game final-game, last-activity now.input.ovum, status %ended, history new-history)
          =/  json=tape
            (make-json-double:three-body new-player-hand dealer-hand-current dealer-score %loss 0 new-bank new-win-loss)
          :_  state(sessions (~(put by sessions.state) game-id final-session))
          ^-  (list effect:http)
          :_  ~
          ^-  effect:http
          :*  %res  id  %200
              :~  ['Content-Type' 'application/json']
                  ['Cache-Control' 'no-cache, no-store, must-revalidate']
              ==
              (to-octs:http (crip json))
          ==
        ::
        ::  Not busted, dealer plays
        =/  final-dealer-hand=hand:three-body  (snag 0 dealer-hand.current-game)
        =/  deck-for-dealer=(list card:three-body)  remaining-deck
        |-
        ?:  (dealer-should-hit:three-body final-dealer-hand)
          =+  [new-card new-deck]=(draw-card:three-body deck-for-dealer)
          $(final-dealer-hand (snoc final-dealer-hand new-card), deck-for-dealer new-deck)
        ::
        ::  Resolve outcome with doubled bet
        =+  [outcome multiplier]=(resolve-outcome:three-body new-player-hand final-dealer-hand)
        =/  payout=@ud  (mul doubled-bet multiplier)
        =/  final-bank=@ud  (add new-bank payout)
        =/  dealer-score=@ud  (hand-value:three-body final-dealer-hand)
        ::
        ::  Calculate win/loss change (payout includes return of bet)
        =/  profit=@sd  (dif:si (sun:si payout) (sun:si doubled-bet))
        =/  new-win-loss=@sd  (sum:si win-loss.current-game profit)
        ::
        ::  Update game (clear bet when ending)
        =/  final-game=game-state-inner:three-body
          current-game(dealer-hand (snap dealer-hand.current-game 0 final-dealer-hand), player-hand (snap player-hand.current-game 0 new-player-hand), deck deck-for-dealer, current-bet 0, bank final-bank, win-loss new-win-loss, game-in-progress %.n)
        ::
        ::  Create history entry
        =/  history-entry=hand-history:three-body
          :*  bet=doubled-bet
              player-hand=new-player-hand
              dealer-hand=final-dealer-hand
              outcome=outcome
              payout=payout
              bank-after=final-bank
              timestamp=now.input.ovum
          ==
        ::  Append to history (keep last N hands per config)
        =/  config=runtime-config:three-body  (get-config state)
        =/  new-history=(list hand-history:three-body)
          (append-to-history:three-body history-entry history.current-session max-history-entries.config)
        ::
        ::  Update session state (set status to ended and add history)
        =/  final-session=session-state:three-body
          current-session(game final-game, last-activity now.input.ovum, status %ended, history new-history)
        ::
        =/  json=tape
          (make-json-double:three-body new-player-hand final-dealer-hand dealer-score outcome payout final-bank new-win-loss)
        ::
        :_  state(sessions (~(put by sessions.state) game-id final-session))
        ^-  (list effect:http)
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Player surrenders
          [%three-body %api game-id:three-body %surrender ~]
        =/  =game-id:three-body  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/surrender route"
        ::  Get session state
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:three-body 404 "Session not found")
          :_  state
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate game action
        =/  validation-error=(unit tape)
          (validate-game-action:three-body %surrender current-session)
        ?^  validation-error
          =/  error-json=tape  (make-json-error:three-body 400 u.validation-error)
          :_  state
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Calculate surrender return (half bet)
        =/  half-bet=@ud  (div current-bet.current-game 2)
        =/  new-bank=@ud  (add bank.current-game half-bet)
        ::
        ::  Calculate win/loss change (lose half the bet)
        =/  profit=@sd  (dif:si (sun:si half-bet) (sun:si current-bet.current-game))
        =/  new-win-loss=@sd  (sum:si win-loss.current-game profit)
        ::
        ::  Update game state
        =/  updated-game=game-state-inner:three-body
          current-game(bank new-bank, win-loss new-win-loss, current-bet 0, game-in-progress %.n)
        ::
        ::  Create history entry
        =/  history-entry=hand-history:three-body
          :*  bet=current-bet.current-game
              player-hand=(snag 0 player-hand.current-game)
              dealer-hand=(snag 0 dealer-hand.current-game)
              outcome=%loss
              payout=half-bet
              bank-after=new-bank
              timestamp=now.input.ovum
          ==
        ::  Append to history
        =/  config=runtime-config:three-body  (get-config state)
        =/  new-history=(list hand-history:three-body)
          (append-to-history:three-body history-entry history.current-session max-history-entries.config)
        ::
        ::  Update session state
        =/  updated-session=session-state:three-body
          current-session(game updated-game, last-activity now.input.ovum, status %ended, history new-history)
        ::
        =/  json=tape
          ;:  weld
            "\{\"outcome\":\"surrendered\""
            ",\"payout\":"
            (a-co:co half-bet)
            ",\"bank\":"
            (a-co:co new-bank)
            ",\"winLoss\":"
            (r-co:co (rlys (san:rs new-win-loss)))
            "}"
          ==
        ::
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :_  ~
        ^-  effect:http
        :*  %res  id  %200
            :~  ['Content-Type' 'application/json']
                ['Cache-Control' 'no-cache, no-store, must-revalidate']
            ==
            (to-octs:http (crip json))
        ==
        ::
          ::  Cash out - withdraw funds from game to player's wallet
          [%three-body %api %wallet %cashout ~]
        ~&  >>  "Matched /three-body/api/wallet/cashout route"
        ::  Parse body to get game-id, player-pkh, and amount
        ?~  body
          =/  error-json=tape  (make-json-error:three-body 400 "Missing request body")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        =/  body-text=tape  (trip q.u.body)
        ~&  >>  "Cashout request body: {<body-text>}"
        ::
        ::  Parse required fields
        =/  game-id-parsed=(unit @t)  (parse-json-text:three-body "gameId" body-text)
        =/  player-pkh-parsed=(unit @t)  (parse-json-text:three-body "playerPkh" body-text)
        =/  amount-parsed=(unit @ud)  (parse-json-number:three-body "amount" body-text)
        ::
        ::  Validate all fields present
        ?~  game-id-parsed
          =/  error-json=tape  (make-json-cashout-tx:three-body '' 0 '' 0 %.n ~ `"Missing gameId field")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ?~  player-pkh-parsed
          =/  error-json=tape  (make-json-cashout-tx:three-body u.game-id-parsed 0 '' 0 %.n ~ `"Missing playerPkh field")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ?~  amount-parsed
          =/  error-json=tape  (make-json-cashout-tx:three-body u.game-id-parsed 0 u.player-pkh-parsed 0 %.n ~ `"Missing amount field")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        =/  =game-id:three-body  u.game-id-parsed
        =/  player-pkh=@t  u.player-pkh-parsed
        =/  amount=@ud  u.amount-parsed
        ~&  >>  "Cashout: game-id={<game-id>}, player-pkh={<player-pkh>}, amount={<amount>}"
        ::
        ::  Validate session exists
        =/  existing=(unit session-state:three-body)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-cashout-tx:three-body game-id amount player-pkh 0 %.n ~ `"Session not found")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        =/  current-session=session-state:three-body  u.existing
        =/  current-game=game-state-inner:three-body  game.current-session
        ::
        ::  Validate no game in progress
        ?:  game-in-progress.current-game
          =/  error-json=tape  (make-json-cashout-tx:three-body game-id amount player-pkh bank.current-game %.n ~ `"Cannot cash out during active game")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Validate sufficient balance
        ?:  (gth amount bank.current-game)
          =/  error-json=tape  (make-json-cashout-tx:three-body game-id amount player-pkh bank.current-game %.n ~ `"Insufficient balance")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Validate minimum cashout amount (at least 1)
        ?:  =(0 amount)
          =/  error-json=tape  (make-json-cashout-tx:three-body game-id amount player-pkh bank.current-game %.n ~ `"Amount must be greater than 0")
          :_  state
          ^-  (list effect:http)
          :_  ~
          [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
        ::
        ::  Deduct amount from bank
        =/  new-bank=@ud  (sub bank.current-game amount)
        ~&  >>  "Cashout approved: {<amount>} from {<bank.current-game>} leaving {<new-bank>}"
        ::
        ::  TODO: Build transaction using wallet tx-builder
        ::  For now, we'll just update the bank and return a success message
        ::  When wallet library is available:
        ::  1. Get server's available notes (UTXOs)
        ::  2. Use tx-builder to construct transaction
        ::  3. Sign with server's private key
        ::  4. Return raw-tx for submission
        ::
        ::  Update game state
        =/  updated-game=game-state-inner:three-body
          current-game(bank new-bank)
        ::
        ::  Update session state
        =/  updated-session=session-state:three-body
          current-session(game updated-game, last-activity now.input.ovum)
        ::
        ::  Build response (tx-ready=%.y if config exists)
        =/  has-tx-config=?  &(?=(^ config.state) ?=(^ private-key.u.config.state))
        =/  json=tape
          (make-json-cashout-tx:three-body game-id amount player-pkh new-bank has-tx-config cashout-tx-hash.updated-session ~)
        ~&  >>  "Cashout completed, returning response"
        ::
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        ^-  (list ?(effect:http effect:wt effect:txt))
        ;:  weld
          ^-  (list effect:http)
          :~  ^-  effect:http
              :*  %res  id  %200
                  :~  ['Content-Type' 'application/json']
                      ['Cache-Control' 'no-cache, no-store, must-revalidate']
                  ==
                  (to-octs:http (crip json))
          ==  ==
          ::  Create transaction effect if config exists
          ?~  config.state
            ~&  >>  "No config state for creating cashout tx effect"
            ^-  (list effect:http)
            ~
          ?~  private-key.u.config.state
            ~&  >>  "No private key in config, cannot create transaction"
            ^-  (list effect:http)
            ~
          ::  Build the transaction effect
          ^-  (list ?(effect:http effect:wt effect:txt))
          :~  %:  create-payout-effect:three-body
                game-id
                wallet-pkh.u.config.state
                u.private-key.u.config.state
                player-pkh
                amount
          ==  ==
        ==
      ==  :: end POST
    ==  :: end GET/POST
  --
--
((moat |) inner)
