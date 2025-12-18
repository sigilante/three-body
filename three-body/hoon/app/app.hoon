::  three-body/app/three-body.hoon
::  Browser-based three-body problem served as a NockApp
::
/+  http, tb=three-body
/=  *  /common/wrapper
::  Static resources (load as [@ud @t])
/*  index         %html   /app/site/index/html
/*  style         %css    /app/site/style/css
/*  game          %js     /app/site/game/js
::  Application state
=>
|%
+$  server-state
  $:  %0
      sessions=(map @t session-state:tb)  :: game-id -> session
  ==
::
::  Default simulation configuration
::
++  default-config
  ^-  sim-config:tb
  :*  gravitational-constant=.1
      timestep=.0.001
      max-trail-length=500
      integration-method=%euler
  ==
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
    ^-  [(list effect:http) server-state]
    ::  Extract entropy from poke input
    =/  entropy=@  eny.input.ovum
    ::
    ::  Parse as HTTP request
    =/  sof-cau=(unit cause:http)  ((soft cause:http) cause.input.ovum)
    ?~  sof-cau
      ~&  "cause incorrectly formatted!"
      ~&  now.input.ovum
      ~&  >  ovum
      !!
    ::  Parse request into components
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
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'text/html']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http q.index)
        ==  ==
        ::
          :: Serve style.css
          [%three-body %'style.css' ~]
        ~&  >>  "Matched route: /three-body/style.css"
        :_  state
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'text/css']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http q.style)
        ==  ==
        ::
          :: Serve game.js
          [%three-body %'game.js' ~]
        ~&  >>  "Matched route: /three-body/game.js"
        :_  state
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'text/javascript']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http q.game)
        ==  ==
        ::
          :: GET /api/sessions - List all active sessions
          [%three-body %api %sessions ~]
        ~&  >>  "Matched route: GET /three-body/api/sessions"
        =/  session-list=(list [game-id=@t status=session-status:tb step-count=@ud])
          %+  turn  ~(tap by sessions.state)
          |=  [gid=@t sess=session-state:tb]
          [gid status.sess step-count.simulation.sess]
        =/  json=tape  (make-json-sessions-list:tb session-list)
        :_  state
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
        ::
          :: GET /api/{game-id}/status - Get simulation state
          [%three-body %api game-id=@t %status ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched route: GET /three-body/api/{<game-id>}/status"
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        =/  json=tape
          (make-json-session-status:tb game-id status.u.existing simulation.u.existing)
        :_  state
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
      ==  :: end GET
      ::
        %'POST'
      ~&  >>  "POST request detected!"
      ?+    uri
        ~&  >>  "No POST route matched for: {<uri>}"
        [~[[%res ~ %500 ~ ~]] state]
        ::
          :: POST /api/session/create - Create new simulation session
          [%three-body %api %session %create ~]
        ~&  >>  "Matched /three-body/api/session/create route"
        ::  Generate UUID from entropy
        =/  game-id=@t  (generate-uuid:tb entropy)
        ~&  >>  "Generated game-id: {<game-id>}"
        ::  Create initial simulation state (figure-eight preset)
        =/  initial-sim=sim-state:tb  preset-figure-eight:tb
        ::  Create session state
        =/  new-session=session-state:tb
          :*  game-id=game-id
              simulation=initial-sim
              preset=`%figure-eight
              created=now.input.ovum
              last-activity=now.input.ovum
              status=%paused
              save-interval=100
              last-saved-step=0
          ==
        ::  Return session info
        =/  json=tape  (make-json-session-created:tb game-id initial-sim)
        ~&  >>  "Created session: {<game-id>}"
        :_  state(sessions (~(put by sessions.state) game-id new-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
        ::
          :: POST /api/{game-id}/step - Advance simulation by N steps
          [%three-body %api game-id=@t %step ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/step route"
        ::  Get session state
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Parse number of steps from body (default: 1)
        =/  num-steps=@ud
          ?~  body  1
          =/  body-text=tape  (trip q.u.body)
          =/  steps-parsed=(unit @ud)  (parse-json-number:tb "steps" body-text)
          ?~(steps-parsed 1 u.steps-parsed)
        ~&  >>  "Advancing simulation by {<num-steps>} steps"
        ::  Run integration steps
        =/  updated-sim=sim-state:tb  simulation.u.existing
        =/  step=@ud  0
        |-
        ?:  (gte step num-steps)
          ::  Return updated state
          =/  updated-session=session-state:tb
            u.existing(simulation updated-sim, last-activity now.input.ovum)
          =/  json=tape  (sim-state-to-json:tb updated-sim)
          :_  state(sessions (~(put by sessions.state) game-id updated-session))
          :~  :*  %res  id  %200
                  :~  ['Content-Type' 'application/json']
                      ['Cache-Control' 'no-cache, no-store, must-revalidate']
                  ==
                  (to-octs:http (crip json))
          ==  ==
        ::  Perform one integration step
        =/  next-sim=sim-state:tb  (integration-step:tb updated-sim)
        $(updated-sim next-sim, step +(step))
        ::
          :: POST /api/{game-id}/play - Start simulation
          [%three-body %api game-id=@t %play ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/play route"
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        =/  updated-session=session-state:tb
          u.existing(status %active, last-activity now.input.ovum)
        =/  json=tape  "\{\"status\":\"active\"}"
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
        ::
          :: POST /api/{game-id}/pause - Pause simulation
          [%three-body %api game-id=@t %pause ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/pause route"
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        =/  updated-session=session-state:tb
          u.existing(status %paused, last-activity now.input.ovum)
        =/  json=tape  "\{\"status\":\"paused\"}"
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
        ::
          :: POST /api/{game-id}/reset - Reset simulation to initial state
          [%three-body %api game-id=@t %reset ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/reset route"
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Reset to the preset that was originally loaded
        =/  reset-sim=sim-state:tb
          ?~  preset.u.existing
            preset-figure-eight:tb
          ?-  u.preset.u.existing
            %figure-eight   preset-figure-eight:tb
            %butterfly      preset-figure-eight:tb  :: TODO: add other presets
            %moth           preset-figure-eight:tb
            %dragonfly      preset-figure-eight:tb
            %yarn           preset-figure-eight:tb
            %goggles        preset-figure-eight:tb
          ==
        =/  updated-session=session-state:tb
          u.existing(simulation reset-sim, status %paused, last-activity now.input.ovum)
        =/  json=tape  (sim-state-to-json:tb reset-sim)
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
      ==  :: end POST
    ==  :: end GET/POST
  --
--
((moat |) inner)
