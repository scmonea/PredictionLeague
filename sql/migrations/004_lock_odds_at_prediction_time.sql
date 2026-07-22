-- Migration: fixes the "stale/moving odds" problem -- previously, scoring
-- read whatever odds happened to be on the fixture when the match
-- finished, so re-running fetch-odds.js after someone had already
-- predicted could silently change what their pick was worth. Now each
-- prediction locks in its own odds at save time, permanently.
--
-- Safe to re-run.

alter table predictions add column if not exists locked_odds numeric;

create or replace function lock_prediction_odds()
returns trigger as $$
declare
  v_fixture fixtures%rowtype;
begin
  select * into v_fixture from fixtures where id = new.fixture_id;
  new.locked_odds := case sign(new.predicted_home_score - new.predicted_away_score)
    when 1 then v_fixture.odds_home
    when -1 then v_fixture.odds_away
    else v_fixture.odds_draw
  end;
  return new;
end;
$$ language plpgsql;

drop trigger if exists on_prediction_lock_odds on predictions;
create trigger on_prediction_lock_odds
  before insert or update on predictions
  for each row
  execute function lock_prediction_odds();

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

create or replace function score_fixture_predictions()
returns trigger as $$
declare
  v_actual_sign int;
begin
  if new.status = 'finished' and new.home_score is not null and new.away_score is not null then
    v_actual_sign := sign(new.home_score - new.away_score);

    update predictions p
    set points = case
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

-- Backfill any predictions that already existed before this migration
-- (they'd otherwise have a null locked_odds) using the fixture's current
-- odds as a best-effort stand-in.
update predictions p
set locked_odds = (
  select case sign(p.predicted_home_score - p.predicted_away_score)
    when 1 then f.odds_home
    when -1 then f.odds_away
    else f.odds_draw
  end
  from fixtures f where f.id = p.fixture_id
)
where p.locked_odds is null;
