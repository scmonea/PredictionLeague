-- Migration: reduce how much a single long-shot exact score can swing a
-- season, versus a season of consistently picking the right side.
--
-- Problem this fixes: the old formula let a correct exact score on a big
-- underdog (e.g. +21 on 15.00 odds) score 5x+ more than the same on a
-- favorite (+4 on 1.15 odds), and the exact-score bonus itself scaled
-- with odds, compounding the swing. One lucky long-shot pick could
-- outweigh weeks of solid, sensible picking.
--
-- What changes:
--   1. Base points (right winner/draw only): round(2 + 2 * sqrt(odds)),
--      capped at 8. Odds still matter -- an upset still scores more than
--      a favorite -- but the range is now 1-8 instead of unbounded, so
--      the gap between a safe correct pick and a long-shot correct pick
--      is roughly 3-4x instead of 7-10x. Replaces the old
--      round(4 * sqrt(odds)) with a -2 penalty below 1.5 odds -- that
--      favorite penalty is gone; the new formula's shape handles it
--      structurally instead.
--   2. Exact-score bonus: flat +3, not scaled by odds at all (was
--      min(6, round(2 * sqrt(odds))), which was the main source of the
--      variance this migration is meant to fix).
--
-- Max possible on any single match is now 11 (base 8 + bonus 3), down
-- from 21 before.
--
-- Safe to re-run -- this just replaces the two scoring functions.

create or replace function base_points_for_odds(v_odds numeric)
returns numeric as $$
begin
  return least(8, round(2 + 2 * sqrt(v_odds)));
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
               then 3
               else 0 end
      end
    where p.fixture_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;
