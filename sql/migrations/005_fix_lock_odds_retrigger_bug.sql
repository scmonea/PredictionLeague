-- Migration: fixes a real bug in 004's lock_prediction_odds trigger -- it
-- fired on EVERY update to a predictions row, including the scoring
-- trigger's own update (which only sets `points`). That meant finishing
-- a fixture silently overwrote locked_odds with whatever the fixture's
-- CURRENT odds were, defeating the point of locking odds at prediction
-- time at all. Fix: only re-lock when the actual predicted score changed.
--
-- Safe to re-run.

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
