// Shared scoring formula, used to show players a live "this would be worth
// about X points" preview while they're choosing a score. The real,
// trusted points are always calculated on the server (the
// score_fixture_predictions() function in sql/schema.sql) -- this file is
// only for the preview, so keep the numbers here in sync with that SQL.

const SCORING = {
  GD_BONUS_CAP: 5,   // goal-difference bonus never exceeds this, however big the margin
  EXACT_BONUS: 3,    // extra points for the exact score, on top of the GD bonus
};

// Correct winner/draw is worth exactly the decimal odds you backed,
// rounded down -- e.g. odds of 3.40 is worth 3 points, odds of 1.15 is
// worth 1. Simple and literal: no square roots, no cap. The bigger the
// underdog, the more it's worth, in direct proportion to how unlikely the
// bookmakers thought it was.
function basePoints(decimalOdds) {
  return Math.floor(decimalOdds);
}

// Scales with how big a correctly-matched goal difference is: a margin
// of 2 goals is worth 1 point, 3 is worth 2, and so on up to the cap. A
// margin of 0 or 1 (a draw, or a 1-0/2-1-style result -- the majority of
// real matches) earns nothing here: this tier only rewards genuinely
// calling a big margin, not just any correct margin. `max(0, ...)`
// handles margins of 0-1 falling below zero before the cap kicks in.
function goalDifferenceBonus(margin) {
  return Math.max(0, Math.min(SCORING.GD_BONUS_CAP, margin - 1));
}

// Three tiers of accuracy, each including everything below it:
//   'winner' -- right side, any score              -> base
//   'gd'     -- right side + matching goal diff.    -> base + GD bonus
//   'exact'  -- the exact score                     -> base + GD bonus + 3
// Matching the exact score always matches the goal difference too (same
// scores mean the same difference), so an exact hit gets both bonuses.
function pointsForPick(decimalOdds, level, gdMargin) {
  const base = basePoints(decimalOdds);
  const gdBonus = goalDifferenceBonus(gdMargin);
  if (level === 'exact') return base + gdBonus + SCORING.EXACT_BONUS;
  if (level === 'gd') return base + gdBonus;
  return base;
}

// Works out which outcome a predicted score represents (home win / draw /
// away win), looks up its odds on the fixture, and returns all three
// hypothetical point values so the UI can show what different levels of
// accuracy on THIS prediction would be worth. The goal-difference margin
// used is the predicted score's own margin -- for "if the actual result
// also has this goal difference" to be true at all, the actual margin
// must equal this one, by definition. Returns null if we don't have odds
// for this fixture yet.
function previewPoints(fixture, predictedHome, predictedAway) {
  let decimalOdds;
  if (predictedHome > predictedAway) decimalOdds = fixture.odds_home;
  else if (predictedHome < predictedAway) decimalOdds = fixture.odds_away;
  else decimalOdds = fixture.odds_draw;

  if (!decimalOdds) return null;

  const gdMargin = Math.abs(predictedHome - predictedAway);
  return {
    ifCorrectWinner: pointsForPick(decimalOdds, 'winner', gdMargin),
    ifCorrectGoalDifference: pointsForPick(decimalOdds, 'gd', gdMargin),
    ifExactScore: pointsForPick(decimalOdds, 'exact', gdMargin),
  };
}

window.previewPoints = previewPoints;
window.pointsForPick = pointsForPick;
