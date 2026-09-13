# Kess Task — Project Status

_Last updated: September 13, 2026_

A Hebrew, right-to-left task and project manager, installable as a PWA. A static
page on GitHub Pages talking straight to Supabase, plus a Google Apps Script that
turns Gmail messages into tasks. No server, no build step, no npm.

This repo previously held an earlier project (an event scraper, "Underground
Radar", which was an early version of what became Kess Time). All of that code
has been removed. Kess Time lives in its own repo now:
https://github.com/kesslernir-code/kessler-time

---

## Architecture

```
  browser / installed PWA                     Google Apps Script (every 15 min)
          |                                    - new Primary-inbox Gmail messages
          v                                    - Gemini 2.5 Flash-Lite: is it a task?
  index.html  (GitHub Pages)                            |
   - Google sign-in (Supabase Auth)                     |  rpc/add_gmail_task
   - projects sidebar, task list, edit modal            |  (token, insert-only)
   - Gmail link on email tasks                          |
          |  supabase-js, publishable key               |
          v                                             v
  Supabase (Postgres, project "underground-radar", free plan)
   - tables: projects, tasks  (RLS: only kesslernir@gmail.com signed in with Google)
   - function: add_gmail_task  (the only way the script can write)
```

## Files

| File | Role |
|---|---|
| `index.html` | The whole app. Hebrew RTL, PWA, supabase-js from jsDelivr. |
| `manifest.json`, `icon.svg` | PWA assets. |
| `apps-script/gmail-to-tasks.gs` | Gmail → Gemini → task. Pasted into script.google.com; not run from this repo. |

## Data

`tasks`: `id, title, description, priority, status, due_date, created_at,
project_id, source ('manual' | 'gmail'), gmail_message_id (unique), gmail_link`.

`projects`: `id, name, created_at`.

`private.gmail_token` holds the SHA-256 of the Apps Script token. The `private`
schema is not exposed through the API.

## Access

- The app uses the **publishable** key, which is public by design. Row Level
  Security limits `tasks` and `projects` to a signed-in user whose JWT email is
  `kesslernir@gmail.com` **and** whose provider is `google` (so an email/password
  sign-up using that address gets nothing).
- The Apps Script can only call `add_gmail_task`, which checks its token and only
  inserts. A leaked token cannot read, edit, or delete tasks. Rotate it by
  storing a new hash in `private.gmail_token` and updating the Script Property.
- The Supabase security advisor flags `add_gmail_task` as a SECURITY DEFINER
  function callable by `anon`. That is intentional.

## Gmail import

- Searches `in:inbox category:primary after:<last check>`, up to 50 threads a run.
- Each message (subject, sender, first 6,000 characters of the body) goes to
  Gemini with a JSON schema; only messages judged to be tasks are saved.
- Duplicates are ignored by the unique `gmail_message_id`. A failed run does not
  advance the checkpoint, so it retries next time; Apps Script emails the owner
  when a trigger fails.
- Needs a **paid-tier** Gemini API key: on the free tier Google may use and
  human-review the content, and its terms say not to send personal information.

## Costs

| Piece | Cost |
|---|---|
| GitHub Pages | free |
| Supabase | free plan (the 15-minute script also keeps the project from pausing for inactivity) |
| Google Apps Script | free (consumer quotas: 20,000 URL fetches/day, 90 min trigger runtime/day) |
| Gemini 2.5 Flash-Lite | paid tier, ~$0.0002 per email at ~1,500 input tokens — roughly $0.60/month at 100 emails/day |

## Running it locally

Serve the folder with any static server and open it. Google sign-in only
returns to URLs listed under Supabase → Authentication → URL Configuration.

## Known open items

- The old scraper tables `places`, `events`, `sources` (empty) and the
  `add_manual_event` function still exist in the Supabase project.
- `node_modules/` from the removed server is still on disk (untracked).
