-- Migration: closes a scoring exploit left open by 005.
--
-- 005 stopped the odds-lock trigger from re-firing on the scoring
-- trigger's own update (which only sets `points`) by skipping whenever
-- the predicted scores were unchanged. But it compared ONLY the scores --
-- not fixture_id. Since 003 grants update on fixture_id (needed for the
-- upsert), a player could:
--
--   1. predict 1-0 on a big underdog, locking locked_odds = 20.0
--   2. PATCH that same row's fixture_id to a different, not-yet-kicked-off
--      fixture, leaving predicted_home_score/predicted_away_score alone
--   3. keep the 20.0 odds on a fixture whose real odds might be 1.4
--
-- The trigger saw unchanged scores, skipped the re-lock, and the stale
-- odds rode along. RLS permits the move -- it's still the player's own
-- row and still before kickoff -- so this is reachable by anyone with the
-- (public, by-design) anon key hitting the REST API directly.
--
-- Fix: only skip the re-lock when the fixture is ALSO unchanged. The
-- scoring trigger's update never touches fixture_id or the scores, so it
-- still skips correctly and 005's fix is preserved.
--
-- Safe to re-run.

create or replace function lock_prediction_odds()
returns trigger as $$
declare
  v_fixture fixtures%rowtype;
begin
  if tg_op = 'UPDATE'
     and old.fixture_id = new.fixture_id
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

-- Deliberately NO backfill/repair of existing rows here.
--
-- It's tempting to "fix up" any prediction whose locked_odds doesn't
-- match its fixture's current odds -- but that's exactly backwards. A
-- locked_odds that differs from the fixture's present odds is the NORMAL,
-- CORRECT state: odds drift after you predict, and preserving the value
-- you saw at save time is the entire point of 004. A repair like that
-- would re-lock every outstanding prediction to today's odds and destroy
-- the very guarantee this file exists to protect.
--
-- There is no way to distinguish "legitimately locked earlier" from
-- "moved via the exploit" after the fact -- both look like a mismatch.
-- So existing rows are left untouched; the trigger fix above prevents it
-- from here on. If you believe someone actually used this, the honest fix
-- is to look at the affected predictions by hand.
