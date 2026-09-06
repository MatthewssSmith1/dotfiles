# Toucan Decoded Layers

US HID legends, not host-layout output. Left/right halves are shown left-to-right.
Positions are zero-based. TRNS = explicit Transparent; UNKNOWN0 = unavailable behavior ID 0, not assumed transparent or None.
MO uses stable layer IDs, not display order. No behavior was executed.

## BASE (order 0, stable ID 0)

```text
Top    Apostrophe  Q  W  E  R  T  ||  Backslash  Y  U  I  O  P
Home   Esc  A  S  D  F  G  ||  ;  H  J  K  L  Enter
Bottom [  Z  X  C  V  B  ||  /  N  M  ,  .  ]
Thumbs Backspace  MO(NAV:id1)  Space  ||  Tab  MO(SYM:id2)  Delete
```

## SYM (order 1, stable ID 2)

```text
Top    Grave  !  @  #  $  %  ||  ^  &  *  (  )  RShift
Home   TRNS  1  2  3  4  5  ||  6  7  8  9  0  TRNS
Bottom ~  A  S  D  F  TRNS  ||  TRNS  _  -  +  =  LShift+RCtrl
Thumbs Backspace  TRNS  Space  ||  Tab  TRNS  Delete
```

## NAV (order 2, stable ID 1)

```text
Top    TRNS  TRNS  TRNS  TRNS  TRNS  TRNS  ||  TRNS  Home  PageDown  PageUp  End  PrintScreen
Home   TRNS  TRNS  TRNS  TRNS  TRNS  MouseRight  ||  TRNS  Left  Down  Up  Right  TRNS
Bottom TRNS  StudioUnlock  TRNS  TRNS  Mouse5  Mouse4  ||  TRNS  TRNS  K_VolumeDown  K_VolumeUp  RShift  RCtrl
Thumbs Backspace  TRNS  Space  ||  Tab  TRNS  Delete
```

## ADJ (order 3, stable ID 3)

```text
Top    MO_INVALID(458795)  F11  F12  TRNS  TRNS  TRNS  ||  TRNS  TRNS  TRNS  TRNS  TRNS  TRNS
Home   LCtrl  F1  F2  F3  F4  F5  ||  F6  F7  F8  F9  F10  TRNS
Bottom LCtrl  LShift  TRNS  TRNS  TRNS  TRNS  ||  TRNS  TRNS  BT_Previous  BT_Next  RShift  RCtrl
Thumbs MO(NAV:id1)  Space  Enter  ||  MO(SYM:id2)  RAlt  UNKNOWN0(0,0)
```
