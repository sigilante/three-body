::  three-body/lib/three-body.hoon
::  Data structures and physics for three-body simulation
::
/+  txt=types
::
/=  ztd  /common/ztd/three
::  Wallet imports (for transaction building)
/=  transact      /common/tx-engine
/=  tx-builder    /apps/wallet/lib/tx-builder
/=  txt           /apps/tx/lib/types
/=  wt            /apps/wallet/lib/types
::
::  three-body/lib/three-body.hoon
::  Physics simulation types and functions
::
=>
|%
::  Vector in 2D space (using signed decimals for position/velocity)
+$  vec2
  $:  x=@rs  :: x-coordinate (single-precision float)
      y=@rs  :: y-coordinate
  ==
::
::  Body/particle in the simulation
+$  body
  $:  pos=vec2        :: position
      vel=vec2        :: velocity
      mass=@rs        :: mass
      color=@t        :: color for visualization (hex color like "ff0000")
  ==
::
::  Simulation configuration
+$  sim-config
  $:  gravitational-constant=@rs    :: G constant (default: .sun:rs)
      timestep=@rs                  :: dt for integration
      max-trail-length=@ud          :: max points in trail history
      integration-method=?(%euler %rk4)  :: integration method
  ==
::
::  Simulation state
+$  sim-state
  $:  bodies=(list body)            :: the three bodies
      time=@rs                      :: current simulation time
      step-count=@ud                :: number of steps taken
      config=sim-config             :: simulation parameters
      trails=(list (list vec2))     :: position history for each body
  ==
::
::  Preset initial conditions (from Observable notebook)
+$  preset-id  ?(%figure-eight %butterfly %moth %dragonfly %yarn %goggles)
::
::  Session and simulation state
+$  game-id  @t  :: UUID-style identifier
::
+$  session-status
  $?  %active          :: Simulation running
      %paused          :: Simulation paused
      %ended           :: Session ended
      %closed          :: Session closed
  ==
::
+$  session-state
  $:  game-id=@t
      simulation=sim-state          :: Current simulation state
      preset=(unit preset-id)       :: Which preset is loaded, if any
      created=@da
      last-activity=@da
      status=session-status
      save-interval=@ud             :: Save state every N steps
      last-saved-step=@ud           :: Last step that was saved
  ==
::
+$  server-config
  $:  wallet-pkh=@t                :: Server's PKH from config
      confirmation-blocks=@ud      :: Required confirmations (typically 3)
      enable-blockchain=?          :: Toggle blockchain integration
      max-history-entries=@ud      :: Maximum history entries to keep (default 20)
  ==
::
::  Runtime server configuration (includes keys and notes)
+$  runtime-config
  $:  wallet-pkh=@t                        :: Server's wallet PKH
      private-key=(unit @t)                :: Server's private key (base58)
      confirmation-blocks=@ud              :: Required confirmations
      enable-blockchain=?                  :: Blockchain integration enabled
      max-history-entries=@ud              :: Max history entries
      notes=(map @t *)                     :: Server's UTXOs (note name -> note data)
  ==
--
::  Physics and math functions
|%
::  Vector operations
++  vec2-add
  |=  [a=vec2 b=vec2]
  ^-  vec2
  [x=(add:rs x.a x.b) y=(add:rs y.a y.b)]
::
++  vec2-sub
  |=  [a=vec2 b=vec2]
  ^-  vec2
  [x=(sub:rs x.a x.b) y=(sub:rs y.a y.b)]
::
++  vec2-mul
  |=  [v=vec2 s=@rs]
  ^-  vec2
  [x=(mul:rs x.v s) y=(mul:rs y.v s)]
::
++  vec2-div
  |=  [v=vec2 s=@rs]
  ^-  vec2
  [x=(div:rs x.v s) y=(div:rs y.v s)]
::
++  vec2-mag-squared
  |=  v=vec2
  ^-  @rs
  (add:rs (mul:rs x.v x.v) (mul:rs y.v y.v))
::
++  vec2-mag
  |=  v=vec2
  ^-  @rs
  (sqt:rs (vec2-mag-squared v))
::
::  Calculate gravitational force on body i due to body j
::  Returns acceleration vector
++  calc-acceleration
  |=  [body-i=body body-j=body g-const=@rs]
  ^-  vec2
  =/  r=vec2  (vec2-sub pos.body-j pos.body-i)
  =/  dist-sq=@rs  (vec2-mag-squared r)
  =/  dist=@rs  (sqt:rs dist-sq)
  ::  Prevent division by zero with softening parameter
  =/  softening=@rs  .1e-2
  =/  softened-dist-sq=@rs  (add:rs dist-sq (mul:rs softening softening))
  ::  F = G * m_j / r^2, but we want acceleration a = F/m_i = G * m_j / r^2
  =/  force-mag=@rs
    (div:rs (mul:rs g-const mass.body-j) softened-dist-sq)
  ::  Direction: r / |r|
  =/  dir=vec2  (vec2-div r dist)
  ::  a = force_mag * direction
  (vec2-mul dir force-mag)
::
::  Calculate total acceleration on one body from all others
++  calc-total-acceleration
  |=  [bodies=(list body) idx=@ud g-const=@rs]
  ^-  vec2
  =/  target=body  (snag idx bodies)
  =/  acc=vec2  [x=.0 y=.0]
  =/  i=@ud  0
  |-
  ?:  (gte i (lent bodies))
    acc
  ?:  =(i idx)
    $(i +(i))
  =/  other=body  (snag i bodies)
  =/  da=vec2  (calc-acceleration target other g-const)
  $(i +(i), acc (vec2-add acc da))
::
::  Euler integration step
++  euler-step
  |=  [state=sim-state]
  ^-  sim-state
  =/  dt=@rs  timestep.config.state
  =/  g=@rs  gravitational-constant.config.state
  ::  Calculate accelerations for all bodies
  =/  accelerations=(list vec2)
    %+  turn  (gulf 0 (dec (lent bodies.state)))
    |=(i=@ud (calc-total-acceleration bodies.state i g))
  ::  Update velocities and positions
  =/  new-bodies=(list body)
    %+  turn  (zip:rlying bodies.state accelerations)
    |=  [b=body acc=vec2]
    ^-  body
    =/  new-vel=vec2
      (vec2-add vel.b (vec2-mul acc dt))
    =/  new-pos=vec2
      (vec2-add pos.b (vec2-mul new-vel dt))
    b(vel new-vel, pos new-pos)
  ::  Update trails
  =/  new-trails=(list (list vec2))
    %+  turn  new-bodies
    |=  b=body
    ^-  (list vec2)
    (scag max-trail-length.config.state ~[pos.b])
  ::  Return updated state
  :*  bodies=new-bodies
      time=(add:rs time.state dt)
      step-count=+(step-count.state)
      config=config.state
      trails=new-trails
  ==
::
::  RK4 integration (4th order Runge-Kutta) - more accurate
++  rk4-step
  |=  [state=sim-state]
  ^-  sim-state
  ::  For now, fall back to Euler (RK4 implementation is complex in Hoon)
  ::  TODO: Implement full RK4
  (euler-step state)
::
::  Perform integration step based on configured method
++  integration-step
  |=  state=sim-state
  ^-  sim-state
  ?-  integration-method.config.state
    %euler  (euler-step state)
    %rk4    (rk4-step state)
  ==
::
::  Helper function to zip two lists (standard library may have this)
++  zip
  |*  [a=(list) b=(list)]
  ^-  (list [* *])
  ?~  a  ~
  ?~  b  ~
  [[i.a i.b] $(a t.a, b t.b)]
::
::  Helper to create rlying (for zip to work with our types)
++  rlying
  |%
  ++  zip
    |*  [a=(list) b=(list)]
    ^-  (list [* *])
    ?~  a  ~
    ?~  b  ~
    [[i.a i.b] $(a t.a, b t.b)]
  --
::
::  Preset initial conditions
::  Figure-8 orbit (Chenciner-Montgomery solution)
++  preset-figure-eight
  ^-  sim-state
  :*  bodies=~
        :*  pos=[x=.~0.97000436 y=.~-0.24308753]
            vel=[x=.~0.466203685 y=.~0.43236573]
            mass=.1
            color='ff0000'
        ==
        :*  pos=[x=.~-0.97000436 y=.~0.24308753]
            vel=[x=.~0.466203685 y=.~0.43236573]
            mass=.1
            color='00ff00'
        ==
        :*  pos=[x=.0 y=.0]
            vel=[x=.~-0.93240737 y=.~-0.86473146]
            mass=.1
            color='0000ff'
        ==
      ==
      time=.0
      step-count=0
      config=:*  gravitational-constant=.1
                 timestep=.~0.001
                 max-trail-length=500
                 integration-method=%euler
             ==
      trails=~[~ ~ ~]
  ==
::
::  Random initial conditions
++  random-initial-state
  |=  ent=@
  ^-  sim-state
  ::  Use entropy to generate random positions/velocities
  ::  For now, return a simple default
  preset-figure-eight
::
::  Helper function to find substring in string
++  find
  |=  [nedl=tape hstk=tape]
  ^-  (unit @ud)
  =|  pos=@ud
  |-
  ?~  hstk  ~
  ::  Check if needle matches at current position
  =/  match=?
    |-  ^-  ?
    ?~  nedl  %.y
    ?~  hstk  %.n
    ?.  =(i.nedl i.hstk)  %.n
    $(nedl t.nedl, hstk t.hstk)
  ?:  match  `pos
  $(hstk t.hstk, pos +(pos))
::
::  JSON encoding helpers
++  vec2-to-json
  |=  v=vec2
  ^-  tape
  ;:  weld
    "\{\"x\":"
    (r-co:co (rlys (san:rs x.v)))
    ",\"y\":"
    (r-co:co (rlys (san:rs y.v)))
    "}"
  ==
::
++  body-to-json
  |=  b=body
  ^-  tape
  ;:  weld
    "\{\"pos\":"
    (vec2-to-json pos.b)
    ",\"vel\":"
    (vec2-to-json vel.b)
    ",\"mass\":"
    (r-co:co (rlys (san:rs mass.b)))
    ",\"color\":\""
    (trip color.b)
    "\"}"
  ==
::
++  bodies-to-json
  |=  bodies=(list body)
  ^-  tape
  ?~  bodies
    "[]"
  =/  json-items=(list tape)
    (turn bodies body-to-json)
  ;:  weld
    "["
    (join-tapes json-items ",")
    "]"
  ==
::
++  sim-state-to-json
  |=  state=sim-state
  ^-  tape
  ;:  weld
    "\{\"bodies\":"
    (bodies-to-json bodies.state)
    ",\"time\":"
    (r-co:co (rlys (san:rs time.state)))
    ",\"stepCount\":"
    (a-co:co step-count.state)
    "}"
  ==
::
++  join-tapes
  |=  [items=(list tape) separator=tape]
  ^-  tape
  ?~  items  ""
  ?~  t.items  i.items
  ;:  weld
    i.items
    separator
    $(items t.items)
  ==
::
::  Session management helpers
++  generate-uuid
  |=  ent=@
  ^-  @t
  ::  Generate UUID-style identifier using entropy
  =/  hex=tape  (scow %ux ent)
  =/  uuid=tape
    ;:  weld
      (scag 8 hex)
      "-"
      (scag 4 (slag 8 hex))
      "-"
      (scag 12 (slag 12 hex))
    ==
  (crip uuid)
::
++  make-json-session-created
  |=  [game-id=@t state=sim-state]
  ^-  tape
  ;:  weld
    "\{\"gameId\":\""
    (trip game-id)
    "\",\"initialState\":"
    (sim-state-to-json state)
    "}"
  ==
::
++  make-json-session-status
  |=  [game-id=@t status=session-status state=sim-state]
  ^-  tape
  ;:  weld
    "\{\"gameId\":\""
    (trip game-id)
    "\",\"status\":\""
    (scow %tas status)
    "\",\"state\":"
    (sim-state-to-json state)
    "}"
  ==
::
++  make-json-error
  |=  [code=@ud message=tape]
  ^-  tape
  ;:  weld
    "\{\"error\":\""
    message
    "\",\"code\":"
    (a-co:co code)
    "}"
  ==
::
++  make-json-sessions-list
  |=  sessions=(list [game-id=@t status=session-status step-count=@ud])
  ^-  tape
  ?~  sessions
    "\{\"sessions\":[]}"
  =/  session-jsons=(list tape)
    %+  turn  sessions
    |=  [game-id=@t status=session-status step-count=@ud]
    ^-  tape
    ;:  weld
      "\{\"gameId\":\""
      (trip game-id)
      "\",\"status\":\""
      (scow %tas status)
      "\",\"stepCount\":"
      (a-co:co step-count)
      "}"
    ==
  ;:  weld
      "\{\"sessions\":["
      (join-tapes session-jsons ",")
      "]}"
  ==
::
++  parse-json-number
  |=  [key=tape json-text=tape]
  ^-  (unit @ud)
  ::  Find the key in the JSON
  =/  key-str=tape  (weld "\"" (weld key "\":"))
  =/  idx=(unit @ud)  (find key-str json-text)
  ?~  idx  ~
  ::  Skip past the key and colon
  =/  remaining=tape  (slag (add u.idx (lent key-str)) json-text)
  ::  Extract digits
  =/  digits=tape
    |-  ^-  tape
    ?~  remaining  ~
    ?:  ?&  (gte i.remaining '0')  (lte i.remaining '9')  ==
      [i.remaining $(remaining t.remaining)]
    ~
  ?~  digits  ~
  `(rash (crip digits) dem)
::
++  parse-json-text
  |=  [key=tape json-text=tape]
  ^-  (unit @t)
  ::  Find the key in the JSON
  =/  key-str=tape  (weld "\"" (weld key "\":\""))
  =/  idx=(unit @ud)  (find key-str json-text)
  ?~  idx  ~
  ::  Skip past the key, colon, and opening quote
  =/  remaining=tape  (slag (add u.idx (lent key-str)) json-text)
  ::  Extract characters until closing quote
  =/  text=tape
    |-  ^-  tape
    ?~  remaining  ~
    ?:  =(i.remaining '"')  ~
    [i.remaining $(remaining t.remaining)]
  ?~  text  ~
  `(crip text)
::
+$  config-poke
  $:  %init-config
      wallet-pkh=@t
      private-key=@t
      confirmation-blocks=@ud
      enable-blockchain=?
      max-history=@ud
  ==
::
::  Causes returned by tx_driver
+$  tx-driver-cause
  $%  [%born ~]
      [%tx-sent game-id=@t tx-hash=@t]
      [%tx-fail game-id=@t error=@t]
  ==
::
+$  update-bank-cause
  $%  [%update-bank p=@ud]
  ==
--
