# Kess-task — Project Status

_Last updated: September 15, 2026_

A Hebrew, right-to-left task and project manager, installable as a PWA. A static
page on GitHub Pages talking straight to Supabase, plus a Google Apps Script that
turns Gmail messages and voice memos into tasks. No server, no build step, no npm.

This repo previously held an earlier project (an event scraper, "Underground
Radar", which was an early version of what became Kess Time). All of that code
has been removed. Kess Time lives in its own repo now:
https://github.com/kesslernir-code/kessler-time

---

## Architecture

```
  browser / installed PWA                     Google Apps Script web app + daily 07:00 trigger
          |                                    - new Primary-inbox Gmail messages
          v                                    - voice memos from the app
  index.html  (GitHub Pages)                   - Gemini 3.5 Flash-Lite
   - Google sign-in (Supabase Auth)                     |
   - task cards (headline) -> details window            |  rpc/add_gmail_task
   - record a task (voice memo)  --- fetch ---------->  |  (token, insert-only)
   - categories sidebar, rename / delete                |
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
| `apps-script/gmail-to-tasks.gs` | Gmail → Gemini → task, and voice memo → task fields. Runs in Apps Script ("kess task gmail"), not from this repo. |
| `apps-script/appsscript.json`, `.clasp.json` | Apps Script manifest (including the web app) and clasp link. |
| `apps-script/deploy.sh` | `clasp push --force`, then points the web app deployment (`deployment-id.txt`) at the new code. Needs clasp, installed globally on C: and logged in as kesslernir@gmail.com. A push replaces every file in the Apps Script project. |
| `apps-script/run.sh` | Calls a runner action through the web app, e.g. `./run.sh dryRun '{"days":14,"limit":30}'`. Reads the runner secret from `~/.kess-task/runner-token.txt` on the local machine. |

## Data

`tasks`: `id, title, description, priority, status, due_date, created_at,
project_id, source ('manual' | 'gmail'), gmail_message_id (unique), gmail_link`.
In the app `title` is the **headline** and `description` the **details**.

`projects` (shown as categories): `id, name, created_at`.

`private.gmail_token` holds the SHA-256 of the Apps Script token. The `private`
schema is not exposed through the API.

`private.tasks_backup_20260915` holds every Gmail task's title and description
from before their headlines and details were regenerated on 2026-09-15.

## The app

- Each task is a card showing its headline and tags (priority, due date, category,
  Gmail, 📝 when it has details). Clicking the card opens a details window with the
  details, the tags, and an edit button.
- **Record a task** (🎤 in the add form): records up to 2 minutes with
  `MediaRecorder`, sends the audio and the signed-in session's access token to the
  web app's `splitRecording`, and fills the headline, details and due date into the
  form for review. The due date is filled only when a date or day is mentioned.
  Nothing is saved until **הוסף** is pressed.
- Categories can be renamed (✎) or deleted (✕) from the sidebar; the buttons show on
  hover and on the selected category.

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

## Web app (`doPost`)

Anonymous access, runs as the owner. Two kinds of caller:

- **Runner** — requests carrying the runner secret, whose SHA-256 is
  `RUNNER_TOKEN_HASH` in the script; the secret stays in
  `~/.kess-task/runner-token.txt`. Actions: `setup`, `checkGmail`, `dryRun`,
  `startBackfill`, `stopBackfill`, `status`, `describeTasks`, `splitRecording`.
- **The app** — requests carrying a Supabase access token. The script asks
  Supabase (`/auth/v1/user`) who the token belongs to and accepts only
  `kesslernir@gmail.com` signed in with Google. Action: `splitRecording` only.

Anything else gets `unauthorized` before any work is done. Responses carry
`result` and the run log.

- `splitRecording` (`audio` base64, `mimeType`): Gemini gets the audio plus today's
  date and weekday in Asia/Jerusalem, and answers in plain text
  `HEADLINE / DETAILS / DUE`. Returns `{ title, description, due_date }`; saves
  nothing.
- `describeTasks` (`tasks: [{ id, gmail_message_id }]`): writes a headline and
  details for each task from its original email; saves nothing, returns proposals.
- `dryRun` (`days`, `offset`, `limit`) reviews conversations like the backfill but
  saves nothing and moves no checkpoint; its log shows sender, subject, and the
  proposed headline, for calibrating the prompt.

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
  `due_date`, `priority`. Then, for tasks only, a plain-text Hebrew headline and
  details (`HEADLINE:` / `DETAILS:`). The headline is kept to one line and 80
  characters, details to 600; a headline that mixes Hebrew and Latin letters inside
  one word is asked for again once and otherwise replaced by the email subject.
  Free text inside JSON made Gemini 3.5 Flash-Lite loop, so headlines and details
  are never JSON.
- The checkpoint (`LAST_MESSAGE_MS`) advances after every message, and a run
  stops itself after 4.5 minutes, so a slow run resumes instead of repeating.
- Duplicates are ignored by the unique `gmail_message_id`. Apps Script emails
  the owner when a trigger fails.
- Needs a **paid-tier** Gemini API key: on the free tier Google may use and
  human-review the content, and its terms say not to send personal information.

### Backfill (one-off)

`startBackfill` imports the last 60 days of Primary-inbox mail into the project
**ייבוא Gmail** (created by `add_gmail_task`'s `p_project_name`) for review. A
5-minute trigger keeps calling `backfill()`, which pages through conversations
with a saved offset (`BACKFILL_OFFSET`) while `BACKFILL_ACTIVE` is `true`, and
removes itself when done. Per conversation only the latest message is checked;
skipped are conversations where the owner sent the last reply (notes to self
still count), automated senders, and tasks whose due date has passed. Mail newer
than the start time (`BACKFILL_UNTIL_MS`) is left to `checkGmail`. Renaming that
category in the app means a future backfill would create a new one.

## Costs

| Piece | Cost |
|---|---|
| GitHub Pages | free |
| Supabase | free plan (the daily script also keeps the project from pausing for inactivity) |
| Google Apps Script | free (consumer quotas: 20,000 URL fetches/day, 90 min trigger runtime/day) |
| Gemini 3.5 Flash-Lite | paid tier, ~$0.0007 per email at ~1,500 input tokens — roughly $2/month at 100 emails/day (2.5 Flash-Lite is closed to new users); voice memos cost a fraction of a cent each |

## Running it locally

Serve the folder with any static server and open it. Google sign-in only
returns to URLs listed under Supabase → Authentication → URL Configuration.

## Known open items

- The old scraper tables `places`, `events`, `sources` (empty) and the
  `add_manual_event` function still exist in the Supabase project.
- `node_modules/` from the removed server is still on disk (untracked).
