# mobileworm Launch Flow Mockups

## Screen 1: First Launch / Connect

```text
+--------------------------------------------------+
|                    mobileworm                    |
|                                                  |
|  Connect to your EarWorm server                  |
|                                                  |
|  [ https://your-earworm-host ]                   |
|                                                  |
|  HTTPS only                                      |
|  Example: https://192.168.1.24:4533              |
|                                                  |
|  [ Connect ]                                     |
|                                                  |
|  Error area                                      |
|  "This server is reachable, but it does not      |
|   appear to be EarWorm."                         |
+--------------------------------------------------+
```

Notes:

- Native SwiftUI screen
- Single text field and one primary action
- Keep copy short and operational

## Screen 2: Validation / Loading

```text
+--------------------------------------------------+
|                    mobileworm                    |
|                                                  |
|                 Connecting to EarWorm            |
|                                                  |
|                     [ spinner ]                  |
|                                                  |
|           Validating server and opening app      |
+--------------------------------------------------+
```

## Screen 3: Embedded EarWorm Login

```text
+--------------------------------------------------+
|  mobileworm                          Change Server|
+--------------------------------------------------+
|                                                  |
|          EarWorm login page in WKWebView         |
|                                                  |
|  [ username ]                                    |
|  [ password ]                                    |
|  [ Sign In ]                                     |
|                                                  |
|  Existing EarWorm mobile browser UI              |
|                                                  |
+--------------------------------------------------+
```

Notes:

- EarWorm owns the full login experience
- Native shell owns the navigation chrome for recovery/change-server only

## Screen 4: Failed Reconnect

```text
+--------------------------------------------------+
|                    mobileworm                    |
|                                                  |
|     Couldn't reconnect to your EarWorm server    |
|                                                  |
|  The saved server did not respond as expected.   |
|                                                  |
|  [ Retry ]                                       |
|  [ Change Server ]                               |
|  [ Open in Safari ]                              |
+--------------------------------------------------+
```

Notes:

- `Open in Safari` is mainly for certificate/trust troubleshooting during TestFlight-era development
