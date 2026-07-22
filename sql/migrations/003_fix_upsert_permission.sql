-- Migration: fixes a real bug -- saving a prediction failed with
-- "permission denied for table predictions" because the app saves picks
-- using an upsert, which needs UPDATE privilege on every column it
-- touches (including player_id and fixture_id, which get re-set to
-- themselves as part of the upsert), but the original grant only covered
-- the score columns.
--
-- Safe to widen: the RLS update policy has no separate WITH CHECK, so its
-- USING clause is automatically re-applied to the new row too -- you
-- still can't reassign a prediction to someone else's player_id or to an
-- already-kicked-off fixture, this just fixes the upsert mechanics.

grant update (player_id, fixture_id, predicted_home_score, predicted_away_score, updated_at)
  on predictions to authenticated;
