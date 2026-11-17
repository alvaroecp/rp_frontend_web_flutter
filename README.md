# rp_frontend_web_flutter
 
## Overview
 
Flutter web application (hereafter the **APP**) that signs in with eSignet 2.0.0 (OpenID Connect) through an RP backend. It is the web version of [rp_frontend_windows_flutter](https://github.com/alvaroecp/rp_frontend_windows_flutter): the screens and the flow are the same.
 
Actors:
 
- **APP**: this project. It runs in the browser and is the one that uses the BACKEND's API.
- **BACKEND**: [rp_backend_dart_frog](https://github.com/alvaroecp/rp_backend_dart_frog). It is the RP towards eSignet and the server towards the APP.
- **BROWSER**: the web browser. It runs the APP and, in a second tab, the page where the USER authenticates with eSignet.
- **USER**: the person who signs in.
- **eSignet**: the identity provider (OpenID Connect server). The local installation used in the tests is described in [esignet_local_docker](https://github.com/alvaroecp/esignet_local_docker).

Features:
 
- Signs in with eSignet through the BACKEND. The APP does not talk to eSignet directly and does not receive its tokens: it only holds the BACKEND's `app_token`, in memory.
- Shows the profile: photo, name and email.
- Shows a Farmer Status screen (`lib/screens/farmer_status_screen.dart`), opened from the profile. It is a mock to simulate an eligibility check: it shows the name of the user and made-up data, such as "Eligible for input subsidy: Yes". It does not call the BACKEND.
- Shows when the session expires, with a live countdown that compares the BACKEND's expiry time with the computer's clock. When it reaches zero, the APP clears its local state, because the session has already expired in the BACKEND.
- Signs out: ends the session in the BACKEND and clears the APP's local state.

Built with Flutter (web, Dart `^3.14.0`), `material_ui` for the Material widgets, `http` for the requests and `web` to open the login tab.
 
**Status.** Learning project. In the tests it worked end to end in Chrome on Windows, with the BACKEND in WSL. Known limitations: the BACKEND's URL is fixed in the code, there is no cancel button while the APP waits for the USER (it waits until the ticket expires, 300 s), some error messages are still in Spanish, the `app_token` is only in memory (reloading the page signs the USER out), only Chrome was tried, and it has no automated tests of its own.
 
## Differences with the desktop APP
 
The code is almost the same. Two things change:
 
| Topic | Desktop APP | Web APP |
| --- | --- | --- |
| Opening the login | `url_launcher` opens the system browser after the ticket arrives | A new tab is opened first, inside the click, and its address is set when the ticket arrives. If the tab were opened after waiting for the BACKEND, the browser might block it as a pop-up |
| Calls to the BACKEND | No restriction | The browser applies CORS: the BACKEND has to allow the APP's origin (see Running) |
 
## Integration with the BACKEND
 
The APP talks only to the BACKEND, by HTTP and JSON. The BACKEND's URL is the constant `backendUrl` in `lib/services/auth_service.dart` (`http://localhost:3005`). The integration lives in that file; the screen is `lib/screens/home_screen.dart`. For the full API, see the BACKEND's README.
 
| Step | What the APP does | BACKEND endpoint | Result |
| --- | --- | --- | --- |
| 1 | Opens an empty tab, then asks for a ticket | `POST /api/login/start` | `ticket`, `poll_secret`, `login_url`, `expires_in` and `interval` |
| 2 | Sets the `login_url` in the new tab | — | The USER authenticates with eSignet there |
| 3 | Polls the status every `interval` seconds | `GET /api/login/status?ticket=…` with the `X-Poll-Secret` header | `pending`, until `complete` with the `app_token`, or `error` |
| 4 | Reads the profile | `GET /api/me` with `Authorization: Bearer <app_token>` | Profile, `sub` and `session_expires_at` |
| 5 | Signs out | `POST /api/logout` with `Authorization: Bearer <app_token>` | `204`. The APP clears its local state even if the call fails |
 
In the tests, the `picture` field of the profile arrived as an inline image (`data:image/jpeg;base64,…`): the APP decodes it and draws it from memory.
 
When something goes wrong:
 
| Situation | What the APP does |
| --- | --- |
| The BROWSER blocks the new tab | Shows an error asking to allow pop-ups for the site |
| `start` does not return `200` | Closes the empty tab and shows an error with the status code |
| `status` does not return `200` (`403`, `404`, `410`…) | Stops polling and shows an error |
| `status` returns `error` | Stops polling and shows an error: the sign-in failed at the provider |
| No `complete` after `expires_in` seconds | Stops polling and shows a timeout error |
| `me` returns `401`, or the countdown reaches zero | Clears its local state and asks the USER to sign in again |
 
## Running
 
Requirements:
 
- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel, Dart `^3.14.0`) with Chrome. It was tested with Flutter 3.50.0 (Dart 3.14.0).
- The BACKEND and eSignet running. See the BACKEND's README, which also says how to create the keys and register the client. In the tests, the BACKEND ran in WSL and the APP reached it through `localhost`.
- A BACKEND with CORS enabled (the browser rule that lets a page read responses from another origin). In the BACKEND it is the `cors()` middleware in `lib/cors_middleware.dart`, which allows one origin, taken from the `ALLOWED_ORIGIN` variable (by default `http://localhost:4200`).

Start the BACKEND first, then run the APP from the project folder:
 
```bash
flutter pub get
flutter run -d chrome --web-port=4200
```
 
The port is fixed so that it matches the allowed origin. Port 3000 is not used because it is taken by eSignet's login interface in the local installation.
 
Press “Sign in with eSignet”: a new tab opens, the USER authenticates with eSignet there, and the APP shows the profile.
 
If the BACKEND is not at `http://localhost:3005`, change `backendUrl` in `lib/services/auth_service.dart`. If the APP runs on another origin, set `ALLOWED_ORIGIN` in the BACKEND.
 
If the BROWSER's console shows a CORS error, the origin of the APP probably does not match `ALLOWED_ORIGIN`, or the BACKEND was not restarted after adding the middleware.
 
## What could be done differently
 
These options were considered and not implemented:
 
- **Sign in on the same tab.** It is the usual way on the web and avoids pop-up blockers. The APP would reload on return, so it would have to keep the ticket (for example in `sessionStorage`), and the BACKEND would have to redirect back to the APP, with a list of allowed destinations.
- **Session in an `HttpOnly` cookie.** It would keep the token out of reach of JavaScript and survive a reload. It needs changes in the BACKEND (cookie, `SameSite`, CORS with credentials).
