-- Migration: replace the sqrt-based, capped base formula with a direct
-- odds-based one -- a correct winner/draw is worth exactly the decimal
-- odds you backed, rounded down. No square roots, no cap.
--
-- Example: odds of 3.40 -> 3 points. Odds of 1.15 -> 1 point. Odds of
-- 15.00 -> 15 points. The exact-score bonus is unchanged (flat +3, from
-- migration 008) -- this migration only touches the winner/draw base.
--
-- Note this reintroduces a wide points range (previously capped at 8 by
-- migration 008) -- a deliberate choice: points now track the bookmakers'
-- odds directly and literally, with no smoothing.
--
-- score_fixture_predictions() itself doesn't need replacing -- it already
-- just calls base_points_for_odds() + a flat 3 for an exact score, so
-- redefining the function below is enough.
--
-- Safe to re-run.

create or replace function base_points_for_odds(v_odds numeric)
returns numeric as $$
begin
  return floor(v_odds);
end;
$$ language plpgsql immutable;
