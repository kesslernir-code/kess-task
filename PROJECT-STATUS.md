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
  browser / installed PWA                     Google Apps Script (daily 07:00)  
          |                                    - new Primary-inbox Gmail messages
          v                                    - Gemini 3.5 Flash-Lite: is it a task?
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
| `apps-script/gmail-to-tasks.gs` | Gmail → Gemini → task. Runs in Apps Script ("kess task gmail"), not from this repo. |
| `apps-script/appsscript.json`, `.clasp.json` | Apps Script manifest (including the web app) and clasp link. |
| `apps-script/deploy.sh` | `clasp push --force`, then points the web app deployment (`deployment-id.txt`) at the new code. Needs clasp, installed globally on C: and logged in as kesslernir@gmail.com. A push replaces every file in the Apps Script project. |
| `apps-script/run.sh` | Calls an action through the web app, e.g. `./run.sh dryRun '{"days":14,"limit":30}'`. Reads the runner secret from `~/.kess-task/runner-token.txt` on the local machine. |

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

- `checkGmail` runs once a day at 07:00 Asia/Jerusalem (set by `setup`). It
  pages through every `in:inbox category:primary` message after the last
  processed one and handles them oldest first.
- Messages from automated senders (no-reply, notification, alert, bounce
  addresses) or carrying a `List-Unsubscribe` header are skipped without calling
  Gemini.
- Every other message (subject, sender, first 6,000 characters of the body) goes
  to Gemini in two calls. First a classification with a JSON schema and no free
  text: `is_task`, `kind` (request / payment / meeting / document / none),
  `due_date`, `priority`. Then, for tasks only, a plain-text Hebrew title, kept
  to its first line and 80 characters, falling back to the email subject. Free
  text inside JSON made Gemini 3.5 Flash-Lite loop, so titles are never JSON.
- The checkpoint (`LAST_MESSAGE_MS`) advances after every message, and a run
  stops itself after 4.5 minutes, so a slow run resumes instead of repeating.
- Duplicates are ignored by the unique `gmail_message_id`. Apps Script emails
  the owner when a trigger fails.
- Needs a **paid-tier** Gemini API key: on the free tier Google may use and
  human-review the content, and its terms say not to send personal information.

### Remote runner

The script is also a web app (`doPost`, anonymous access, runs as the owner).
It does nothing unless the request carries the runner secret, whose SHA-256 is
`RUNNER_TOKEN_HASH` in the script; the secret itself stays in
`~/.kess-task/runner-token.txt`. Actions: `setup`, `checkGmail`, `dryRun`,
`startBackfill`, `stopBackfill`, `status`. The response carries the run log.

`dryRun` (`days`, `offset`, `limit`) reviews conversations like the backfill but
saves nothing and moves no checkpoint; its log shows sender, subject, and the
proposed title, for calibrating the prompt.

### Backfill (one-off)

`startBackfill` imports the last 60 days of Primary-inbox mail into the project
**ייבוא Gmail** (created by `add_gmail_task`'s `p_project_name`) for review. A
5-minute trigger keeps calling `backfill()`, which pages through conversations
with a saved offset (`BACKFILL_OFFSET`) while `BACKFILL_ACTIVE` is `true`, and
removes itself when done. Per conversation only the latest message is checked;
skipped are conversations where the owner sent the last reply (notes to self
still count), automated senders, and tasks whose due date has passed. Mail newer
than the start time (`BACKFILL_UNTIL_MS`) is left to `checkGmail`.

## Costs

| Piece | Cost |
|---|---|
| GitHub Pages | free |
| Supabase | free plan (the daily script also keeps the project from pausing for inactivity) |
| Google Apps Script | free (consumer quotas: 20,000 URL fetches/day, 90 min trigger runtime/day) |
| Gemini 3.5 Flash-Lite | paid tier, ~$0.0007 per email at ~1,500 input tokens — roughly $2/month at 100 emails/day (2.5 Flash-Lite is closed to new users) |

## Running it locally

Serve the folder with any static server and open it. Google sign-in only
returns to URLs listed under Supabase → Authentication → URL Configuration.

## Known open items

- The old scraper tables `places`, `events`, `sources` (empty) and the
  `add_manual_event` function still exist in the Supabase project.
- `node_modules/` from the removed server is still on disk (untracked).
