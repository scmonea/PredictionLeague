-- Migration: run this once in your Supabase SQL Editor to add a "favorite
-- penalty" to scoring: correctly backing a heavy favorite (odds below 1.5)
-- now scores 2 points less (floored at a minimum of 1), since it's a much
-- safer pick than a toss-up or underdog. Everything at odds 1.5+ (draws,
-- underdogs) is unchanged, as is the exact-score bonus.
--
-- Safe to re-run -- this just replaces the scoring function.

create or replace function score_fixture_predictions()
returns trigger as $$
declare
  v_outcome_odds numeric;
  v_actual_sign int;
  v_base numeric;
begin
  if new.status = 'finished' and new.home_score is not null and new.away_score is not null then
    v_actual_sign := sign(new.home_score - new.away_score);
    v_outcome_odds := case v_actual_sign
      when 1 then new.odds_home
      when -1 then new.odds_away
      else new.odds_draw
    end;

    v_base := round(4 * sqrt(v_outcome_odds));
    if v_outcome_odds < 1.5 then
      v_base := greatest(1, v_base - 2);
    end if;

    update predictions p
    set points = case
      when v_actual_sign is distinct from sign(p.predicted_home_score - p.predicted_away_score)
        then 0
      else
        v_base
        + case when p.predicted_home_score = new.home_score and p.predicted_away_score = new.away_score
               then least(6, round(2 * sqrt(v_outcome_odds)))
               else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;
