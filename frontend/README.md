# Swirl client

The desktop UI is authored in Jac under `frontend/client/`. Jac compiles those
components to React for the Tauri webview; `frontend/src/index.css` remains the
shared stylesheet.

From this directory:

- `npm run dev` starts the Jac client development server.
- `npm run build` writes the web assets to `.jac/client/dist`.
- `npm test` runs the Jac backend and client-domain suites.
- `npm run tauri:dev` and `npm run tauri:build` wrap that client with the
  existing native macOS boundary.
