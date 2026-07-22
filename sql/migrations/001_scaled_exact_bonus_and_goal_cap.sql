-- Migration: run this once in your Supabase SQL Editor to bring an
-- already-set-up project (one where you already ran the original
-- sql/schema.sql) up to date with two changes:
--
--   1. Predicted scores are capped at 0-15 goals per side.
--   2. The exact-score bonus now scales with odds (like the base points
--      do) instead of always being a flat +6 -- but is capped at 6, so
--      nobody gets less than before, and nobody's bonus runs away either.
--
-- Safe to run even if you're not sure whether you've already applied it --
-- the constraint add is skipped if it already exists, and the function
-- replace is always safe to re-run.

alter table predictions
  add constraint predictions_predicted_home_score_check check (predicted_home_score between 0 and 15);

alter table predictions
  add constraint predictions_predicted_away_score_check check (predicted_away_score between 0 and 15);

create or replace function score_fixture_predictions()
returns trigger as $$
declare
  v_outcome_odds numeric;
  v_actual_sign int;
begin
  if new.status = 'finished' and new.home_score is not null and new.away_score is not null then
    v_actual_sign := sign(new.home_score - new.away_score);
    v_outcome_odds := case v_actual_sign
      when 1 then new.odds_home
      when -1 then new.odds_away
      else new.odds_draw
    end;

    update predictions p
    set points = case
      when v_actual_sign is distinct from sign(p.predicted_home_score - p.predicted_away_score)
        then 0
      else
        round(4 * sqrt(v_outcome_odds))
        + case when p.predicted_home_score = new.home_score and p.predicted_away_score = new.away_score
               then least(6, round(2 * sqrt(v_outcome_odds)))
               else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;
