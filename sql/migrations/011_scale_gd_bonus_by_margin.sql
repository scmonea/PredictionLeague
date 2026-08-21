-- Migration: replace the flat +1 goal-difference bonus (010) with one
-- that scales by how big the correctly-matched margin is.
--
-- A matched goal difference of 2 is worth 1 point, 3 is worth 2, and so
-- on up to a cap of 5 (a margin of 6 or more). A margin of 0 or 1 -- a
-- draw, or a result like 1-0/2-1, which covers most real matches -- earns
-- nothing from this tier: it's meant to reward correctly calling a
-- genuinely big margin, not just any correct one.
--
-- Example: actual result is a 4-1 home win (goal difference +3).
--   Predict 1-0 (+1)  -- no GD match -> no bonus
--   Predict 3-0 (+3)  -- GD matches, margin 3 -> +2
--   Predict 5-2 (+3)  -- GD matches, margin 3 -> +2 (same as above: same
--                        margin, same bonus, regardless of exact score)
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
               then greatest(0, least(5, abs(v_actual_gd) - 1))
               else 0 end
        + case when p.predicted_home_score = new.home_score and p.predicted_away_score = new.away_score
               then 3 else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;
