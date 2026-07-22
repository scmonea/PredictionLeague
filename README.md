# Prediction League

A score-prediction game for friends, like a Premier League predictor pool --
except instead of a flat 2 points for the right result / 3 for the exact
score, points scale with how unlikely the bookmakers thought your pick was.
Calling a big underdog correctly is worth a lot more than calling a heavy
favorite. See "How scoring works" below for the exact formula.

This is a learning project (first app!) so it's deliberately built with
plain HTML/CSS/JS -- no frameworks, no build step, no npm for the website
itself. The only place Node.js is used is one small script that fetches
odds data (see below).

## What you need to set up once

Three free accounts, plus two secret keys pasted into files that never get
committed to git.

### 1. Supabase (the database)

1. Create a free account at [supabase.com](https://supabase.com) and a new project.
2. In your project, go to **Authentication -> Providers** and enable **Anonymous sign-ins** (off by default). This is how players get "logged in" just by visiting the site, no password needed -- fine for a friends-only test.
3. Go to **SQL Editor -> New query**, paste in the entire contents of [`sql/schema.sql`](sql/schema.sql), and run it. This creates the three tables the app needs (`players`, `fixtures`, `predictions`) and locks them down so players can only edit their own data.
4. Go to **Project Settings -> API** and note down:
   - **Project URL**
   - **anon public** key
   - **service_role** key (keep this one secret!)

### 2. The Odds API (real betting odds)

1. Create a free account at [the-odds-api.com](https://the-odds-api.com/) (500 free requests/month, no card needed).
2. Copy your API key from the dashboard.

### 3. Wire up the keys

**Frontend (safe to be public):** open [`supabase-client.js`](supabase-client.js) and replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_ANON_KEY` with your real Project URL and anon key from step 1.4. This file is fine to commit -- the anon key is designed to be public; the real security is the database rules from `schema.sql`.

**Backend script (must stay secret):**
```
cp .env.example .env
```
Then edit `.env` and fill in `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `ODDS_API_KEY`. `.env` is gitignored -- it will never be committed.

## Running it

```
npm install
npm run fetch-odds     # pulls upcoming EPL fixtures + odds into Supabase
```

Then just open `index.html` in a browser (or use a local server -- either works, this site needs no build step). You should see fixtures once you visit `predict.html`.

Re-run `npm run fetch-odds` before each gameweek to refresh fixtures and odds, and `npm run fetch-results` after matches finish to pull in final scores (see "Entering final results" below) -- both a 10-second ritual, no need to automate further yet. See "Weekly timeline" below for exactly when to run each one.

## How scoring works

Only win/draw/lose odds (not exact-score odds) are reliably available for
free, so the formula is:

- **Wrong winner/draw:** 0 points.
- **Right winner/draw:** `round(4 * sqrt(decimal odds of that outcome))` points -- minus 2 (floored at 1) if the odds were below **1.5**, since backing a heavy favorite is a much safer pick than a toss-up or underdog and shouldn't score quite the same.
- **+ exact-score bonus** on top if the scoreline was also exactly right: `round(2 * sqrt(same odds))`, capped at **6** so a huge longshot can't blow the bonus up indefinitely.

Both the base points and the bonus scale with how unlikely the pick was --
correctly calling a big underdog is worth more, and *nailing the exact
score* on a big underdog is worth more too (up to the cap). What doesn't
matter is how big the scoreline itself is: predicting a 10-0 win is worth
exactly the same as predicting 1-0 for the same team, since the formula
only cares which side you backed and whether you hit the exact score --
not the goal count. (Predicted scores are capped at 0-15 per side anyway,
mostly just to stop silly numbers.)

Worked examples:

| Odds picked | Correct winner only | + exact score |
|---|---|---|
| 1.15 (very heavy favorite) | 2 | 4 |
| 1.30 (heavy favorite) | 3 | 5 |
| 1.50+ (no penalty from here up) | 5 | 7 |
| 2.00 (toss-up) | 6 | 9 |
| 3.40 (draw) | 7 | 11 |
| 8.00+ (underdog) | scales up | capped at base + 6 |
| 20.00 (huge longshot) | 18 | 24 |

The favorite penalty only applies below 1.50 odds; the bonus hits its +6
cap once odds reach about 8-9, so from there up only the base points keep
climbing.

These numbers (`4`, `2`, and the cap of `6`) live in one place in
[`league-scoring.js`](league-scoring.js) (the live preview players see
while picking) and are mirrored in the scoring function in
[`sql/schema.sql`](sql/schema.sql) (which computes the real, trusted
points) -- tweak both together if you want to change the feel. If your
Supabase project already exists, run any new files in
[`sql/migrations/`](sql/migrations) (in order) once in the SQL Editor to
bring it up to date -- currently
[`001_scaled_exact_bonus_and_goal_cap.sql`](sql/migrations/001_scaled_exact_bonus_and_goal_cap.sql),
[`002_favorite_penalty.sql`](sql/migrations/002_favorite_penalty.sql),
[`003_fix_upsert_permission.sql`](sql/migrations/003_fix_upsert_permission.sql)
(fixes a real bug where saving any pick failed with "permission denied for
table predictions" -- run it even if scoring feels fine, since it's what
actually lets predictions save at all),
[`004_lock_odds_at_prediction_time.sql`](sql/migrations/004_lock_odds_at_prediction_time.sql)
(see "Weekly timeline" below for why),
[`005_fix_lock_odds_retrigger_bug.sql`](sql/migrations/005_fix_lock_odds_retrigger_bug.sql)
(run this even if you already ran 004 -- it fixes a bug where finishing a
fixture could silently overwrite everyone's locked odds), and
[`006_relock_odds_on_fixture_change.sql`](sql/migrations/006_relock_odds_on_fixture_change.sql)
(closes a scoring exploit 005 left open -- because 005 only compared the
predicted scores, a player could lock in a big underdog's odds and then
move that prediction to a different fixture, keeping the generous odds.
Run this one before you share the site with anyone).

Points are always calculated server-side, in the database, triggered
automatically when a fixture's result is entered -- never trusted from the
browser, so nobody can edit their own score.

## Weekly timeline

A normal Premier League gameweek runs **Friday evening through Monday
night** (Friday night game, several Saturday kickoffs, a couple of Sunday
games, often a Monday night finale). Tuesday-Thursday are normally free of
EPL fixtures. The recommended weekly rhythm:

1. **Tuesday** (or whenever suits that week) -- run `npm run fetch-odds`.
   This is safely after every match from the previous gameweek has
   finished (including a Monday night game), so you're never touching a
   gameweek that's still in progress. It pulls in the next batch of
   fixtures with fresh odds.
2. **Tuesday through kickoff** -- players can predict (or change their
   mind) on any fixture, right up until *that specific match's* kickoff --
   each fixture locks independently, not the whole gameweek at once.
3. **The moment you save a pick**, the odds for your chosen outcome are
   captured permanently into that prediction (`locked_odds` in the
   database). Re-running `fetch-odds` later -- even for the same
   fixture -- can never change what an already-saved pick is worth. This
   is what makes the timeline unambiguous: whatever you saw when you hit
   save is what you're scored against, full stop.
4. **After the gameweek's matches finish** -- run `npm run fetch-results`
   to pull in final scores and trigger scoring.

## Prediction rules

- You can change your pick as many times as you like right up until kickoff -- each edit re-locks fresh odds for your new pick.
- Once a fixture kicks off, your prediction locks -- no edits, even mid-match. This was a deliberate choice (a "change your pick when a team scores" mode was considered and dropped) to keep it simple and avoid rewarding whoever happens to be watching live over friends who are busy.
- Once a fixture kicks off, everyone can see everyone else's prediction for it (before kickoff, you can only see your own) -- click a name on the leaderboard to see a player's full prediction history.

## Entering final results

```
npm run fetch-results
```

Run this after a gameweek's matches finish. It checks The Odds API's free
`/scores` endpoint for completed games and updates the matching fixtures
(`home_score`, `away_score`, `status='finished'`), which automatically
triggers scoring for every prediction on that fixture. Safe to run multiple
times -- it skips fixtures already marked finished.

If a match isn't showing up yet (API hasn't settled it, or something looks
off), you can always fix it by hand instead: open the Supabase Table
Editor, find the fixture in the `fixtures` table, and fill in `home_score`,
`away_score`, and `status` yourself -- same trigger fires either way.

## Getting it online for friends

1. Push this repo to a new GitHub repository.
2. In the repo's **Settings -> Pages**, enable GitHub Pages for the `main` branch. You'll get a free `https://yourname.github.io/reponame/` link to share.
3. On a phone, friends can open that link and tap **Add to Home Screen** (Safari) or the install prompt (Chrome on Android) to get an app-like icon and full-screen launch -- no app store needed.

## Automating fetch-odds and fetch-results (optional)

Once this repo is on GitHub, [`.github/workflows/`](.github/workflows) has two
scheduled workflows that run your existing scripts for you, for free, using
GitHub Actions:

- **fetch-odds.yml** -- every Tuesday morning.
- **fetch-results.yml** -- every 4 hours, every day (harmless on days with nothing finished).

To enable them: go to the repo's **Settings -> Secrets and variables ->
Actions**, and add three **repository secrets** with the same values as
your local `.env`: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`ODDS_API_KEY`. That's it -- no server, no extra account. You can also
trigger either workflow manually any time from the repo's **Actions** tab
(each has a "Run workflow" button). Running the manual `npm run
fetch-odds` / `npm run fetch-results` commands locally still works too,
as a fallback if a scheduled run ever fails silently or a fixture needs a
manual fix.

## Later: a real App Store / Play Store app

If the group likes this enough to want a "real" installed app, the
recommended path is wrapping this same website with
[Capacitor](https://capacitorjs.com/) rather than rewriting it -- since
this app is just forms and tables (not graphically demanding), that wrap
needs very little extra work and lets you submit to the App Store ($99/yr
Apple Developer account) and Google Play ($25 one-time). None of the
Supabase database, security rules, or scoring logic would need to change
for that move.

## Project structure

```
index.html            Leaderboard (landing page) -- click a name for their prediction history
predict.html           Submit/edit your picks for upcoming fixtures
fixtures.html           Full fixture list: upcoming odds + past results
player.html             One player's full prediction history (linked from the leaderboard)
styles.css               Shared styling for every page
supabase-client.js        Supabase connection + anonymous sign-in + name claim + HTML-escaping helper
league-scoring.js          Scoring formula (shared with the SQL trigger, kept in sync by hand)
manifest.json / service-worker.js / icons/   PWA "Add to Home Screen" support
scripts/fetch-odds.js       Node script: pulls odds from The Odds API into Supabase (run manually or via GitHub Actions)
scripts/fetch-results.js     Node script: pulls finished-match scores from The Odds API, triggers scoring (run manually or via GitHub Actions)
sql/schema.sql                Database tables + security rules + scoring trigger (run once in Supabase)
.github/workflows/             Scheduled automation for fetch-odds.js / fetch-results.js (optional, see above)
```
