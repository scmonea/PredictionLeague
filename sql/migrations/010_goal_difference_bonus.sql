-- Migration: add a third scoring tier between "right side" and "exact
-- score" -- a flat +1 for matching the actual goal difference, even when
-- the exact score isn't right.
--
-- Example: actual result is a 2-1 home win (goal difference +1). A
-- prediction of 1-0 for the same team (also +1) now scores the odds
-- points AND the +1 goal-difference bonus, even though the score itself
-- wasn't exact. A prediction of 3-0 (+3) only scores the odds points --
-- right side, wrong goal difference.
--
-- The three tiers now stack like this (each requires the right side):
--   right side, any score              -> base_points_for_odds(odds)
--   + goal difference also matches     -> +1
--   + the exact score                  -> +3 more (implies GD matches too)
--
-- base_points_for_odds() itself is unchanged -- only
-- score_fixture_predictions() needs replacing.
--
-- Safe to re-run.

create or replace function score_fixture_predictions()
returns trigger as $$
declare
  v_actual_sign int;
  v_actual_gd int;
begin
  if new.status = 'finished' and new.home_score is not null and new.away_score is not null then
    v_actual_sign := sign(new.home_score - new.away_score);
    v_actual_gd := new.home_score - new.away_score;

    update predictions p
    set points = case
      when v_actual_sign is distinct from sign(p.predicted_home_score - p.predicted_away_score)
        then 0
      else
        base_points_for_odds(p.locked_odds)
        + case when (p.predicted_home_score - p.predicted_away_score) = v_actual_gd
               then 1 else 0 end
        + case when p.predicted_home_score = new.home_score and p.predicted_away_score = new.away_score
               then 3 else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;
