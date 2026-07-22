-- Run this whole file once in the Supabase SQL editor
-- (your project -> SQL Editor -> New query -> paste this in -> Run).
--
-- It creates the three tables the app needs and locks them down with
-- Row Level Security (RLS) so players can only ever see/change what
-- they're supposed to.

-- ============================================================
-- players: one row per friend, linked to their anonymous login
-- ============================================================
create table players (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique not null references auth.users(id) on delete cascade,
  display_name text not null unique,
  created_at timestamptz not null default now()
);

alter table players enable row level security;

-- Anyone can see everyone's name (needed for the leaderboard).
create policy "players are viewable by everyone"
  on players for select
  using (true);

-- You can only ever create a player row for YOUR OWN login session.
create policy "players can insert their own row"
  on players for insert
  with check (auth.uid() = auth_user_id);


-- ============================================================
-- fixtures: matches + odds, written only by scripts/fetch-odds.js
-- ============================================================
create table fixtures (
  id uuid primary key default gen_random_uuid(),
  external_id text unique,           -- The Odds API's event id, so re-fetching updates instead of duplicating
  home_team text not null,
  away_team text not null,
  kickoff_at timestamptz not null,
  odds_home numeric,
  odds_draw numeric,
  odds_away numeric,
  odds_fetched_at timestamptz,
  home_score int,
  away_score int,
  status text not null default 'scheduled'  -- 'scheduled' | 'finished' | 'postponed'
);

alter table fixtures enable row level security;

-- Everyone can see fixtures + odds (they need this to make predictions).
create policy "fixtures are viewable by everyone"
  on fixtures for select
  using (true);

-- No insert/update/delete policy is defined for normal users on purpose --
-- with RLS enabled, that means those actions are denied by default. The
-- fetch-odds.js script uses the secret service_role key instead, which
-- bypasses RLS entirely. That's what stops a player from editing the odds
-- or faking a match result.
revoke insert, update, delete on fixtures from anon, authenticated;


-- ============================================================
-- predictions: one row per player per fixture
-- ============================================================
create table predictions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references players(id) on delete cascade,
  fixture_id uuid not null references fixtures(id) on delete cascade,
  predicted_home_score int not null check (predicted_home_score between 0 and 15),
  predicted_away_score int not null check (predicted_away_score between 0 and 15),
  locked_odds numeric,                -- odds for the picked outcome, captured the moment this row was saved -- never by a player, see the trigger below
  points numeric,                     -- filled in automatically by the trigger below, never by a player
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (player_id, fixture_id)
);

alter table predictions enable row level security;

-- You can always see your own picks. You can only see OTHER players'
-- picks for a fixture once it has kicked off -- this is what stops
-- people copying each other's predictions before a match starts.
create policy "predictions are visible to owner always, others after kickoff"
  on predictions for select
  using (
    player_id in (select id from players where auth_user_id = auth.uid())
    or (select kickoff_at from fixtures where id = fixture_id) <= now()
  );

-- You can only insert your own prediction, and only before kickoff.
create policy "players can insert their own prediction before kickoff"
  on predictions for insert
  with check (
    player_id in (select id from players where auth_user_id = auth.uid())
    and (select kickoff_at from fixtures where id = fixture_id) > now()
  );

-- You can only edit your own prediction, and only before kickoff.
create policy "players can update their own prediction before kickoff"
  on predictions for update
  using (
    player_id in (select id from players where auth_user_id = auth.uid())
    and (select kickoff_at from fixtures where id = fixture_id) > now()
  );

-- The two policies above control which ROWS a player can touch, but RLS
-- alone doesn't stop someone from also sneaking a fake value into the
-- `points` column of a row they're otherwise allowed to write. Postgres
-- has a separate, column-level permission system for that: we only grant
-- insert/update rights on the columns a player should legitimately set,
-- so `points` and `locked_odds` (and `id`, `created_at`) can only ever be
-- written by the triggers below, which run with elevated privileges.
--
-- player_id and fixture_id are included in the UPDATE grant (not just
-- predicted_home_score/predicted_away_score) because saving a pick uses
-- an upsert, which re-sets every provided column -- including those two
-- -- even when it ends up taking the "update" branch. It's still safe to
-- let players "update" their own player_id/fixture_id: the update policy
-- above has no separate WITH CHECK, so Postgres reuses its USING clause
-- to validate the row AFTER the update too, meaning you can't reassign a
-- prediction to someone else's player_id or to a fixture that's already
-- kicked off -- the same rule just gets re-checked against the new values.
revoke insert, update on predictions from anon, authenticated;
grant insert (player_id, fixture_id, predicted_home_score, predicted_away_score)
  on predictions to authenticated;
grant update (player_id, fixture_id, predicted_home_score, predicted_away_score, updated_at)
  on predictions to authenticated;


-- ============================================================
-- Locking odds: whatever the fixture's odds are for your picked outcome
-- (home/draw/away) at the moment you save a prediction, that's what gets
-- captured into `locked_odds` and used for scoring later -- permanently,
-- no matter how many times fetch-odds.js refreshes that fixture's odds
-- afterward (e.g. because it also picked up next gameweek's fixtures in
-- the same run). This is what makes the timeline unambiguous: your score
-- is always based on exactly what you saw when you hit save.
--
-- Runs BEFORE insert/update so it can set the value on the row being
-- written, same trick as `updated_at` defaults -- and it re-fires on
-- every edit, so changing your mind before kickoff re-locks fresh odds
-- for your new pick, as it should.
--
-- Important: this trigger fires on EVERY update to a predictions row, not
-- just ones where a player changes their pick -- the scoring trigger
-- below also updates this same row (to fill in `points`) once a fixture
-- finishes. If we blindly re-locked odds every time, that later update
-- would silently overwrite the odds you actually predicted against with
-- whatever the fixture's odds happen to be by then, defeating the whole
-- point. So: only re-lock when predicted_home_score/predicted_away_score
-- actually changed (or it's a brand new row) -- otherwise leave
-- locked_odds exactly as it was.
-- ============================================================
create or replace function lock_prediction_odds()
returns trigger as $$
declare
  v_fixture fixtures%rowtype;
begin
  if tg_op = 'UPDATE'
     and old.predicted_home_score = new.predicted_home_score
     and old.predicted_away_score = new.predicted_away_score then
    return new;
  end if;

  select * into v_fixture from fixtures where id = new.fixture_id;
  new.locked_odds := case sign(new.predicted_home_score - new.predicted_away_score)
    when 1 then v_fixture.odds_home
    when -1 then v_fixture.odds_away
    else v_fixture.odds_draw
  end;
  return new;
end;
$$ language plpgsql;

create trigger on_prediction_lock_odds
  before insert or update on predictions
  for each row
  execute function lock_prediction_odds();


-- ============================================================
-- Scoring: a function that turns locked-in odds into points, reused by
-- both the live preview math you can eyeball here and the real trigger
-- below. Formula: round(4 * sqrt(odds)), minus 2 (floored at 1) if odds
-- were below 1.5 -- backing a heavy favorite is a safer pick, so it's
-- worth a little less even when you're right.
--
-- Keep this in sync with league-scoring.js, which shows players the same
-- numbers as a live preview before kickoff.
-- ============================================================
create or replace function base_points_for_odds(v_odds numeric)
returns numeric as $$
begin
  if v_odds < 1.5 then
    return greatest(1, round(4 * sqrt(v_odds)) - 2);
  else
    return round(4 * sqrt(v_odds));
  end if;
end;
$$ language plpgsql immutable;

-- Fills in `points` automatically whenever a fixture's result is set
-- (home_score/away_score/status updated to 'finished' -- normally done by
-- scripts/fetch-results.js, see the README). Scores every prediction
-- against its OWN locked_odds, not the fixture's current odds.
create or replace function score_fixture_predictions()
returns trigger as $$
declare
  v_actual_sign int;   -- 1 = home win, -1 = away win, 0 = draw
begin
  if new.status = 'finished' and new.home_score is not null and new.away_score is not null then
    v_actual_sign := sign(new.home_score - new.away_score);

    update predictions p
    set points = case
      -- Predicted a different winner/draw than what actually happened.
      when v_actual_sign is distinct from sign(p.predicted_home_score - p.predicted_away_score)
        then 0
      else
        base_points_for_odds(p.locked_odds)
        + case when p.predicted_home_score = new.home_score and p.predicted_away_score = new.away_score
               then least(6, round(2 * sqrt(p.locked_odds)))
               else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_fixture_result_set
  after update on fixtures
  for each row
  execute function score_fixture_predictions();
