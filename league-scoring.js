// Shared scoring formula, used to show players a live "this would be worth
// about X points" preview while they're choosing a score. The real,
// trusted points are always calculated on the server (the
// score_fixture_predictions() function in sql/schema.sql) -- this file is
// only for the preview, so keep the numbers here in sync with that SQL.

const SCORING = {
  BASE: 4,                        // multiplies sqrt(odds) for a correct winner/draw
  FAVORITE_ODDS_THRESHOLD: 1.5,   // odds below this count as a "heavy favorite"
  FAVORITE_PENALTY: 2,            // points subtracted for correctly backing a heavy favorite
  MIN_CORRECT_PICK_POINTS: 1,     // a correct pick is never worth less than this
  EXACT_BONUS_MULTIPLIER: 2,      // multiplies sqrt(odds) for the exact-score bonus...
  EXACT_BONUS_CAP: 6,             // ...but the bonus never goes above this
};

// Backing a heavy favorite (short odds) is a much safer pick than backing
// a toss-up or an underdog, so it's worth a bit less even when you're
// right -- everything at or above the threshold is untouched.
function basePoints(decimalOdds) {
  let points = Math.round(SCORING.BASE * Math.sqrt(decimalOdds));
  if (decimalOdds < SCORING.FAVORITE_ODDS_THRESHOLD) {
    points = Math.max(SCORING.MIN_CORRECT_PICK_POINTS, points - SCORING.FAVORITE_PENALTY);
  }
  return points;
}

// The exact-score bonus scales with odds like the base points do (nailing
// an underdog's exact score is worth more than nailing a favorite's), but
// is capped so a wild longshot can't blow the bonus up indefinitely.
function exactScoreBonus(decimalOdds) {
  return Math.min(SCORING.EXACT_BONUS_CAP, Math.round(SCORING.EXACT_BONUS_MULTIPLIER * Math.sqrt(decimalOdds)));
}

// decimalOdds: the odds for whichever outcome (home/draw/away) was picked.
function pointsForCorrectPick(decimalOdds, isExactScore) {
  const base = basePoints(decimalOdds);
  return base + (isExactScore ? exactScoreBonus(decimalOdds) : 0);
}

// Works out which outcome a predicted score represents (home win / draw /
// away win), looks up its odds on the fixture, and returns both possible
// point values so the UI can show "X pts if just the winner, Y pts if the
// exact score". Returns null if we don't have odds for this fixture yet.
function previewPoints(fixture, predictedHome, predictedAway) {
  let decimalOdds;
  if (predictedHome > predictedAway) decimalOdds = fixture.odds_home;
  else if (predictedHome < predictedAway) decimalOdds = fixture.odds_away;
  else decimalOdds = fixture.odds_draw;

  if (!decimalOdds) return null;

  return {
    ifCorrectWinner: pointsForCorrectPick(decimalOdds, false),
    ifExactScore: pointsForCorrectPick(decimalOdds, true),
  };
}

window.previewPoints = previewPoints;
