# Kess Task — Project Status

_Last updated: September 12, 2026_

A Hebrew, right-to-left task and project manager, installable as a PWA, backed by
Supabase. One HTML frontend, one plain-Node backend, no framework.

This repo previously held an earlier project (an event scraper, "Underground
Radar", which was an early version of what became Kess Time). All of that code
has been removed — the scraper, its daily GitHub Actions workflow, and the
place-discovery script. Kess Time lives in its own repo now:
https://github.com/kesslernir-code/kessler-time

---

## Architecture

```
      browser / installed PWA
                 |
                 v
      index.html  (vanilla HTML + CSS + JS, Hebrew RTL)
       - projects sidebar
       - task list, add + edit modal
       - "add to Google Calendar" links
                 |
                 |  fetch /api/*
                 v
      server.js  (node:http, ~180 lines, no framework)
       - serves index.html
       - serves inline PWA assets (icon.svg, manifest.json)
       - proxies task/project CRUD to Supabase
                 |
                 v
      Supabase (Postgres)
       - tables: projects, tasks
```

## Files

| File | Role |
|---|---|
| `index.html` | The whole frontend. Hebrew RTL, PWA. |
| `server.js` | HTTP server and the `/api` layer over Supabase. |
| `nixpacks.toml` | Deploy config: node 22, `npm install`, `node server.js`. |
| `package.json` | Two runtime deps: `@supabase/supabase-js`, `dotenv`. |

`icon.svg` and `manifest.json` are not files — `server.js` holds them as inline
constants (`ICON_SVG`, `MANIFEST`) and serves them from memory.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/` , `/index.html` | the app |
| GET | `/icon.svg` , `/manifest.json` | PWA assets, served inline |
| GET | `/api/projects` | list projects |
| POST | `/api/projects` | create a project |
| DELETE | `/api/projects/:id` | delete a project |
| GET | `/api/tasks` | list tasks (accepts query filters) |
| POST | `/api/tasks` | create a task |
| PATCH | `/api/tasks/:id` | update a task |
| DELETE | `/api/tasks/:id` | delete a task |

CORS allows `GET, POST, PATCH, DELETE, OPTIONS`.

## Environment

`server.js` reads these (via `dotenv`, from `.env`, which is gitignored):

- `SUPABASE_URL`
- `SUPABASE_KEY`
- `PORT` (optional)

## Running it

This repo lives on a Google Drive File Stream path (`G:`). **Do not run
`npm install` inside that folder** — the Drive filesystem makes npm's tar
extraction fail silently, producing zero-byte files while npm reports success.
Install into a local folder and copy `node_modules` across with `robocopy`
instead.

```
node server.js        # then open http://localhost:3000/  (or $PORT)
```

## Hosting

- GitHub Pages is enabled on this repo and serves `index.html` statically.
  Note that the static-only Pages copy has no `/api` backend behind it.
- `nixpacks.toml` targets a container host (Railway) running `node server.js`,
  which is what serves the API.

## Known open items

- `package-lock.json` and `package.json` had drifted apart (the lockfile pinned
  `dotenv@17.4.2` while `package.json` asked for `^16.4.5`), which broke
  `npm ci`. The lockfile has been regenerated from the pruned dependency list.
- GitHub Pages still serves from the repo root, so the Pages URL changes with
  the repo name.
