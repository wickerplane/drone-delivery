;; global variables
globals [
    stop-list
    num-existing-drones ;;how many drones are currently active
    num-existing-trucks ;;how many trucks currently active
    drone-waitlist ;;packages waiting to be delivered by drones
    drone-waittimes ;;how long each package has been waiting
    truck-waitlist ;;packages waiting to be delivered by trucks
    truck-waittimes ;;how long each package has been waiting
    drone-times ;; list of time it took to deliver a drone package, for averaging
    truck-times ;; list of time it took to deliver a truck package, for averaging
    quadrant-num ;; number for assigning trucks to an area of the map
    drone-rechargelist ;;drones waiting to be recharged
    num-stops ;;number of packages/stops generated in total
]

breed [ drones drone ]
breed [ trucks truck ]

drones-own [
  deliver-time ;; how long did it take to deliver this package?
  dest-stop ;; where is it going to deliver the package?
  speed ;; how fast the drone moves
  just-created ;; was it just created? (disappearing bug fix)
  total-distance ;; how far did it go?
]

trucks-own [
  waitlist-time ;; total time the packages spent waiting in waitlist
  update-fixed-time-cost
  total-distance
  total-time
  area
  truck-stops
  speed
  just-created
  current-index
]

to setup
  clear-all

  ;;graphical things? like colors, an amazon center representation at middle
  ask patch 0 0 [set pcolor red]

  ;; intialize global variables
  set stop-list []
  set drone-waitlist []
  set truck-waitlist []
  set drone-waittimes []
  set truck-waittimes []
  set drone-times []
  set truck-times []
  set drone-rechargelist []
  set num-existing-drones 0
  set num-existing-trucks 0
  set quadrant-num 0
  set num-stops 0


  reset-ticks
end

to go
  ;; drones that need recharging get recharged one tick
   recharge-drones


  ;;potentially create a package based on probability
  if (random-package) [
    ;; increase total number of stops
    set num-stops num-stops + 1
    ;;generate the random stop
    ask patch 0 0 [generate-stops]

    ;; generate drones as needed up to max
    ;; based on condition that the number of active and recharging drones <= max number of drones
    ifelse ((num-existing-drones + length drone-rechargelist) <= max-drones) [generate-drone]
    ;; if not enough drones available, add it to the waitlist
    [
      set drone-waitlist lput last stop-list drone-waitlist
      set drone-waittimes lput 0 drone-waittimes
    ]

    ;; generate trucks as needed up to max (they don't get sent out until capacity)
    if(num-existing-trucks < max-trucks) [generate-truck]

    ;;add the new package to a truck's stop list
    let package last stop-list
    assign-package (package) ;; inside assing-package also assigns them to
    ;; a waitlist if no trucks are available

;    print word "truck waitlist " length truck-waitlist
;    print word "drone waitlist " length drone-waitlist
  ]

   ;;look through waitlist of packages and assign them to drones or trucks
   ;;if they are available
   assign-truck-waitlist
   assign-drone-waitlist

  ;; ask all active drones to move
  move-drone ;;carrying single packages

  ;; truck movement/delivery- trucks don't move until loaded at or above a threshold
  ask trucks [
     if (length truck-stops / truck-capacity >= truck-delivery-threshold)  [
       move-truck
     ]
  ]

  ;; update waitlist times for packages in waitlists
  update-waits



  ;;TODO: something with the cost

   tick
end

;; Recharges each drone that needs to be recharged
to recharge-drones
  let index 0
  foreach drone-rechargelist [
    [x] ->
     set drone-rechargelist replace-item index drone-rechargelist (x - (1 / 2.133333))
     ;; if they're fully recharged, remove them from the recharge list
     if (x <= 0) [
       set drone-rechargelist remove-item index drone-rechargelist
       set index index - 1
     ]
     set index index + 1
  ]

end

;;Assign a package to a truck- package is a patch here
;; if no trucks are available that are appropriate, assign it to waitlist
to assign-package [package]
  let assigned false

  ;;increment time for fixed time cost of loading for each truck waiting
  ask trucks-on patch 0 0 [
    set total-time total-time + (1 / 2.133333)
  ]

  ;;assign the packages depending on where the package is going
  ask package [
    if (pxcor >= 0 and pycor >= 0) [
      ask trucks [
        ;; make sure the truck is going to the right area and the package has
        ;; not yet been assigned
        if (area mod 4 = 0 and not assigned) [
          ;; make sure we're within the truck's capacity and that it's in the loading area
          if(length truck-stops <= truck-capacity and xcor = 0 and ycor = 0) [
            set truck-stops lput package truck-stops
            set assigned true
          ]
        ]
      ]
      if (not assigned)[
        set truck-waitlist lput package truck-waitlist
        set truck-waittimes lput 0 truck-waittimes
      ]
    ]
    if (pxcor < 0 and pycor >= 0) [
      ask trucks [
        if (area mod 4 = 1 and not assigned) [
          if (length truck-stops <= truck-capacity and xcor = 0 and ycor = 0) [
            set truck-stops lput package truck-stops
            set assigned true
          ]
        ]
      ]
      if (not assigned)[
        set truck-waitlist lput package truck-waitlist
        set truck-waittimes lput 0 truck-waittimes
      ]
    ]
    if (pxcor >= 0 and pycor < 0) [
      ask trucks [
        if (area mod 4 = 2 and not assigned) [
          if (length truck-stops <= truck-capacity and xcor = 0 and ycor = 0) [
            set truck-stops lput package truck-stops
            set assigned true
          ]
        ]
      ]
       if (not assigned)[
        set truck-waitlist lput package truck-waitlist
        set truck-waittimes lput 0 truck-waittimes
      ]
    ]
    if (pxcor < 0 and pycor < 0) [
      ask trucks [
        if (area mod 4 = 3 and not assigned) [
         if (length truck-stops <= truck-capacity and xcor = 0 and ycor = 0) [
            set truck-stops lput package truck-stops
            set assigned true
          ]
        ]
      ]
      if (not assigned)[
        set truck-waitlist lput package truck-waitlist
        set truck-waittimes lput 0 truck-waittimes
      ]
    ]
  ]

end

;;essentially if there are packages in the waitlist, try to assign them to trucks to send them out
to assign-truck-waitlist
  let index 0
  let trucks-waiting trucks-on patch 0 0
  let assigned false
  foreach truck-waitlist [
    [package] ->
    ask package [
       set assigned false
       ;;assign waitlist packages based on area the truck is going to
    if (pxcor >= 0 and pycor >= 0) [
      ask trucks-waiting [
        if (area mod 4 = 0 and not assigned) [
          if(length truck-stops <= truck-capacity) [
            set truck-stops lput package truck-stops
            set assigned true
            ;;update wait time for truck to be included in delivery time
            let waittime item index truck-waittimes
            set waitlist-time waitlist-time + waittime
          ]
        ]
      ]
    ]
    if (pxcor < 0 and pycor >= 0) [
      ask trucks-waiting [
        if (area mod 4 = 1 and not assigned) [
          if (length truck-stops <= truck-capacity) [
            set truck-stops lput package truck-stops
            set assigned true
             ;;update wait time for truck
            let waittime item index truck-waittimes
            set waitlist-time waitlist-time + waittime
          ]
        ]
      ]
    ]
    if (pxcor >= 0 and pycor < 0) [
      ask trucks-waiting [
        if (area mod 4 = 2 and not assigned) [
          if (length truck-stops <= truck-capacity) [
            set truck-stops lput package truck-stops
            set assigned true
             ;;update wait time for truck
            let waittime item index truck-waittimes
            set waitlist-time waitlist-time + waittime
          ]
        ]
      ]
    ]
    if (pxcor < 0 and pycor < 0) [
      ask trucks-waiting [
        if (area mod 4 = 3 and not assigned) [
         if (length truck-stops <= truck-capacity) [
            set truck-stops lput package truck-stops
            set assigned true
             ;;update wait time for truck
            let waittime item index truck-waittimes
            set waitlist-time waitlist-time + waittime
          ]
        ]
      ]
    ]
  ]
    if (assigned) [;;remove from waitlist
            set truck-waitlist remove-item index truck-waitlist
            set truck-waittimes remove-item index truck-waittimes
            set index index - 1
    ]

    set index index + 1
  ]
end

;;essentially if there are packages in the waitlist, try to assign them to drones to send them out
to assign-drone-waitlist
  let index 0
    foreach drone-waitlist [
      [package] ->
        ;;create a drone if it's within the max condition
        ifelse ((num-existing-drones + length drone-rechargelist) <= max-drones) [
            ;;NOTE: slightly different from generate-drone
            create-drones 1 [
              setxy 0 0 ;; puts it at the amazon center to begin with
              set color blue
              ;; include how long the package was waiting in the delivery time
              set deliver-time item index drone-waittimes
              set shape "airplane"
              set dest-stop package
              set num-existing-drones (num-existing-drones + 1)
              set just-created true
              set total-distance 0.0
            ]
            ;;remove from waitlist
            set drone-waitlist remove-item index drone-waitlist
            set drone-waittimes remove-item index drone-waittimes
            set index index - 1

        ]    [stop] ;;if we're at the max num drones, stop looping

     set index index + 1
    ]

end

;;generates a single drone
to generate-drone
  create-drones 1 [
    setxy 0 0 ;; puts it at the amazon center to begin with
    set color blue
    set deliver-time 0.0
    set shape "airplane"
    set dest-stop last stop-list
    set num-existing-drones (num-existing-drones + 1)
    set just-created true
    set total-distance 0.0
  ]
end

;;generates a single truck
to generate-truck
  create-trucks 1 [
    setxy 0 0 ;; puts it at the amazon center to begin with
    ;;initialize truck variables
    set color green
    set shape "car"
    set truck-stops []
    set num-existing-trucks (num-existing-trucks + 1)
    set just-created true
    set area quadrant-num
    if (quadrant-num >= max-trucks - 1) [
      set quadrant-num -1
    ]
    set quadrant-num quadrant-num + 1
    set current-index 0
    set total-distance 0.0
    set total-time 0.0
    set update-fixed-time-cost true
    set waitlist-time 0.0
  ]

end

;;see if you generated a package this tick
to-report random-package
  let prob false
  ifelse (random 100 < package-prob) [set prob true] [set prob false]
  report prob
end

;; choose a patch to deliver to randomly
to generate-stops
    let chosen-patch one-of other patches
    set stop-list lput chosen-patch stop-list
    ask chosen-patch [
      set pcolor yellow
    ]
end

;; increment wait times for all the packages in waitlists
to update-waits
 let index 0
  foreach drone-waittimes [
    [x] ->
      set drone-waittimes replace-item index drone-waittimes (x + (1 / 2.133333))
      set index (index + 1)
  ]
  set index 0
  foreach truck-waittimes [
    [x] ->
      set truck-waittimes replace-item index truck-waittimes (x + (1 / 2.133333))
      set index (index + 1)
  ]
end

;; move drones
to move-drone
  ask drones [
    set speed drone-speed
    ;; has the drone arrived at the destination?
    if (patch-here = dest-stop) [
     set dest-stop patch 0 0
     ask patch-here [
       ;; if the drone was the first to arrive, set it pink, or if truck was first, revert to black patch
       ifelse (pcolor = gray) [
         set pcolor black
       ][set pcolor pink]
     ]
    ]

    ;; error checking
    if (dest-stop = patch 0 0 and just-created) [
      die
    ]

    ;; send drone directly towards destination
    set heading towards dest-stop
    forward speed
    ;; update total distance traveled
    set total-distance total-distance + speed

    ;; if this is not the origin patch, the drone is no longer just created
    if (patch-here != patch 0 0) [set just-created false]

    ;; update delivery time
    set deliver-time (deliver-time + (1 / 2.133333))
    ;; if this patch is the origin and it wasn't just created, the drone has come back to origin
    if (patch-here = patch 0 0 and not just-created) [
      ;; decrement number of existing drones
      set num-existing-drones (num-existing-drones - 1)
      ;; add time to all drone delivery times- always half of total travel time because towards and back
      set drone-times lput (deliver-time / 2) drone-times
      ;; add an element to be recharged- drones have to be recharged
      set drone-rechargelist lput drone-recharge-time drone-rechargelist
      ;;kill this drone
      die
    ]
  ]
end

;; move all the trucks that should be moved
to move-truck

    ;; adjust speed of truck based on traffic speed
    set speed (traffic-speed / 100)

    ;; add the loading time to the truck's total delivery time
    if update-fixed-time-cost [
      set update-fixed-time-cost false
      set total-time (total-time * (length truck-stops) / 2)
    ]

let current-stop patch 0 0
;; if we've gotten through all the stops the truck needs to make, go back to origin
ifelse (current-index >= length truck-stops) [
  let curr-x 0
  let curr-y 0
  ask patch-here [
    set curr-x pxcor
    set curr-y pycor
  ]
  ;; move to origin in taxi cab way
  ifelse (curr-x != 0) [
    set heading towards patch 0 curr-y
  ] [
    set heading towards patch 0 0
  ]
][

  ;;otherwise, move to next destination in the stop list
  set current-stop item current-index truck-stops
  let x-direction 0
  let y-direction 0
  ask current-stop [
    set x-direction pxcor
    set y-direction pycor
  ]
  let curr-x 0
  let curr-y 0
  ask patch-here [
    set curr-x pxcor
    set curr-y pycor
  ]
  ;; move in a taxi cab way
  ifelse (curr-x != x-direction) [
    set heading towards patch x-direction curr-y
  ] [
    ifelse (curr-y != y-direction) [
      set heading towards patch x-direction y-direction
    ] [
      ;;package delivered
      ask patch-here [
       ifelse (pcolor = pink) [
         set pcolor black
       ][set pcolor gray]
     ]
      set current-index current-index + 1
    ]
  ]
]
    ;;go forward based on speed
    forward speed
    set total-distance total-distance + speed
    set total-time total-time + (1 / 2.133333)

    if (patch-here != patch 0 0) [set just-created false]

    ;; if this is the origin, die/recharge
    if (patch-here = patch 0 0 and not just-created) [
      ;;calculate average time
      let average-time 0
      ;;include the time that items were in the waitlist
      set total-time total-time + waitlist-time
      set average-time total-time / (length truck-stops)
      ;; add the average time to all truck delivery times
      set truck-times lput average-time truck-times
      set truck-stops []
      ;;decrement existing number of trucks
      set num-existing-trucks (num-existing-trucks - 1)
      ;; kill the truck
      die
    ]
end

;;average drone delivery time
to-report average-drone-time
  ifelse (length drone-times = 0) [report 0]
  ;; convert to actual time in minutes- multiply by 0.6
  ;; the reason for 0.6 is because the turtles move in
  ;; 1/100 of an hour intervals (each tick = 1/100 of an hour,
  ;; or 0.6 minutes per tick
  [ report (mean drone-times) * 0.6]
end

;;average truck delivery time
to-report average-truck-time
  ifelse (length truck-times = 0) [report 0]
  ;; convert to actual time in minutes- multiply by 0.6
  ;; the reason for 0.6 is because the turtles move in
  ;; 1/100 of an hour intervals (each tick = 1/100 of an hour,
  ;; or 0.6 minutes per tick
  [report (mean truck-times) * 0.6]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
647
448
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

SLIDER
23
28
195
61
max-stops
max-stops
50
300
208.0
1
1
NIL
HORIZONTAL

SLIDER
24
70
196
103
traffic-speed
traffic-speed
10
75
25.0
1
1
NIL
HORIZONTAL

SLIDER
21
120
193
153
max-trucks
max-trucks
5
40
38.0
1
1
NIL
HORIZONTAL

SLIDER
21
167
193
200
max-drones
max-drones
10
400
355.0
1
1
NIL
HORIZONTAL

SLIDER
22
214
194
247
truck-capacity
truck-capacity
25
200
107.0
1
1
NIL
HORIZONTAL

BUTTON
23
445
86
478
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
95
445
158
478
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
22
256
194
289
package-prob
package-prob
0
100
59.0
1
1
NIL
HORIZONTAL

SLIDER
13
301
200
334
truck-delivery-threshold
truck-delivery-threshold
0
1
0.6
0.05
1
NIL
HORIZONTAL

PLOT
680
39
945
235
Average Delivery Times
Ticks
Average truck delivery time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"pen-1" 1.0 0 -2674135 true "" "plot average-drone-time"
"pen-2" 1.0 0 -13840069 true "" "plot average-truck-time"

MONITOR
683
276
857
321
Average Drone Delivery Time
average-drone-time
5
1
11

MONITOR
682
324
853
369
Average Truck Delivery Time
average-truck-time
5
1
11

SLIDER
30
349
202
382
drone-recharge-time
drone-recharge-time
0
50
30.0
1
1
NIL
HORIZONTAL

SLIDER
20
395
192
428
drone-speed
drone-speed
0
0.5
0.134
0.002
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
