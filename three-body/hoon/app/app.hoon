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
        ::
          :: GET /api/presets/{preset-id} - Load a preset configuration
          [%three-body %api %presets preset-id=@t ~]
        =/  preset-id=@t  (snag 3 `path`uri)
        ~&  >>  "Matched route: GET /three-body/api/presets/{<preset-id>}"
        ::  Parse preset ID
        =/  parsed-preset=(unit preset-id:tb)  ((soft preset-id:tb) preset-id)
        ?~  parsed-preset
          ~&  >>>  "Invalid preset ID: {<preset-id>}"
          =/  error-json=tape  (make-json-error:tb 400 "Invalid preset ID")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Load the preset
        =/  preset-sim=sim-state:tb  (load-preset:tb u.parsed-preset)
        =/  json=tape  (sim-state-to-json:tb preset-sim)
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
          (load-preset:tb u.preset.u.existing)
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
        ::
          :: POST /api/{game-id}/checkpoint - Save current simulation state
          [%three-body %api game-id=@t %checkpoint ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/checkpoint route"
        ::  Get session state
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Parse checkpoint data from body
        ?~  body
          =/  error-json=tape  (make-json-error:tb 400 "Missing checkpoint data")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Parse JSON body
        =/  body-text=tape  (trip q.u.body)
        ~&  >>  "Checkpoint body: {<body-text>}"
        ::
        ::  Parse step count and time
        =/  step-count-parsed=(unit @ud)  (parse-json-number:tb "stepCount" body-text)
        =/  time-parsed=(unit @ud)  (parse-json-number:tb "time" body-text)
        ::
        ?~  step-count-parsed
          ~&  >>>  "Failed to parse stepCount from checkpoint"
          =/  error-json=tape  (make-json-error:tb 400 "Invalid checkpoint data")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::
        ::  Update simulation state with checkpoint data
        ::  For now, just update step count and time as integers
        ::  TODO: Parse full bodies array for complete state restoration
        =/  current-sim=sim-state:tb  simulation.u.existing
        =/  updated-sim=sim-state:tb
          current-sim(step-count u.step-count-parsed, time (sun:rs (fall time-parsed 0)))
        ::
        ::  Update session with new simulation state
        =/  updated-session=session-state:tb
          u.existing(simulation updated-sim, last-activity now.input.ovum, last-saved-step u.step-count-parsed)
        ::
        ~&  >>  "Checkpoint saved: step={<u.step-count-parsed>} for session {<game-id>}"
        =/  json=tape  "\{\"success\":true,\"message\":\"Checkpoint saved\",\"step\":{<(a-co:co u.step-count-parsed)>}}"
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
      ::
      ::  POST /api/{game-id}/load-preset/{preset-id} - Load a new preset into session
      [%three-body %api game-id=@t %load-preset preset-id=@t ~]
        =/  game-id=@t  (snag 2 `path`uri)
        =/  preset-id=@t  (snag 4 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/load-preset/{<preset-id>} route"
        ::  Verify session exists
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Parse preset ID
        =/  parsed-preset=(unit preset-id:tb)  ((soft preset-id:tb) preset-id)
        ?~  parsed-preset
          ~&  >>>  "Invalid preset ID: {<preset-id>}"
          =/  error-json=tape  (make-json-error:tb 400 "Invalid preset ID")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Load the new preset
        =/  new-sim=sim-state:tb  (load-preset:tb u.parsed-preset)
        ::  Update session with new preset and simulation
        =/  updated-session=session-state:tb
          u.existing(simulation new-sim, preset `u.parsed-preset, status %paused, last-activity now.input.ovum)
        ::  Return the new simulation state
        =/  json=tape  (sim-state-to-json:tb new-sim)
        ~&  >>  "Loaded preset {<preset-id>} into session {<game-id>}"
        :_  state(sessions (~(put by sessions.state) game-id updated-session))
        :~  :*  %res  id  %200
                :~  ['Content-Type' 'application/json']
                    ['Cache-Control' 'no-cache, no-store, must-revalidate']
                ==
                (to-octs:http (crip json))
        ==  ==
      ::
      ::  POST /api/{game-id}/advance - Execute N physics steps server-side
      [%three-body %api game-id=@t %advance ~]
        =/  game-id=@t  (snag 2 `path`uri)
        ~&  >>  "Matched /three-body/api/{<game-id>}/advance route"
        ::  Verify session exists
        =/  existing=(unit session-state:tb)  (~(get by sessions.state) game-id)
        ?~  existing
          ~&  >>>  "Session not found: {<game-id>}"
          =/  error-json=tape  (make-json-error:tb 404 "Session not found")
          :_  state
          :~  [%res id %404 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Verify body exists
        ?~  body
          =/  error-json=tape  (make-json-error:tb 400 "Missing request body")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::  Parse the number of steps to advance from request body
        =/  body-text=tape  (trip q.u.body)
        ~&  >>  "Advance body: {<body-text>}"
        ::
        =/  steps-parsed=(unit @ud)  (parse-json-number:tb "steps" body-text)
        ?~  steps-parsed
          ~&  >>>  "Failed to parse steps from advance request"
          =/  error-json=tape  (make-json-error:tb 400 "Invalid advance request: missing 'steps' parameter")
          :_  state
          :~  [%res id %400 ~[['Content-Type' 'application/json']] (to-octs:http (crip error-json))]
          ==
        ::
        ::  Cap steps at 1000 to prevent excessive computation
        =/  steps-to-advance=@ud  (min u.steps-parsed 1.000)
        ~&  >>  "Advancing simulation by {<steps-to-advance>} steps"
        ::
        ::  Execute physics steps on server
        =/  current-sim=sim-state:tb  simulation.u.existing
        =/  updated-sim=sim-state:tb
          =/  i=@ud  0
          |-
          ?:  =(i steps-to-advance)
            current-sim
          $(current-sim (integration-step:tb current-sim), i +(i))
        ::
        ::  Update session
        =/  updated-session=session-state:tb
          u.existing(simulation updated-sim, last-activity now.input.ovum)
        ::
        ::  Build JSON response with updated state
        =/  bodies-json=tape
          =/  body-jsons=(list tape)
            %+  turn  bodies.updated-sim
            |=  b=body:tb
            =/  x-str=tape  (r-co:co (drg:rs x.pos.b))
            =/  y-str=tape  (r-co:co (drg:rs y.pos.b))
            =/  vx-str=tape  (r-co:co (drg:rs x.vel.b))
            =/  vy-str=tape  (r-co:co (drg:rs y.vel.b))
            =/  mass-str=tape  (r-co:co (drg:rs mass.b))
            "\{\"pos\":\{\"x\":{x-str},\"y\":{y-str}},\"vel\":\{\"x\":{vx-str},\"y\":{vy-str}},\"mass\":{mass-str},\"color\":\"{(trip color.b)}\"}"
          (join-tapes:tb body-jsons ",")
        ::
        =/  time-str=tape  (r-co:co (drg:rs time.updated-sim))
        =/  json=tape
          "\{\"bodies\":[{bodies-json}],\"time\":{time-str},\"stepCount\":{<(a-co:co step-count.updated-sim)>}}"
        ::
        ~&  >>  "Advanced to step {<step-count.updated-sim>}"
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
