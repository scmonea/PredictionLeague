// Checks The Odds API for finished Premier League results and updates the
// matching fixtures in Supabase (home_score, away_score, status='finished').
// That update is what triggers the scoring function in sql/schema.sql,
// which fills in points for every prediction on that fixture.
//
// Run this after a gameweek's matches have finished:
//
//   npm run fetch-results
//
// Like fetch-odds.js, this runs on your computer via `node`, never in the
// browser -- it uses the secret service_role key to write to `fixtures`.

import 'dotenv/config';
import fetch, { Headers, Request, Response } from 'node-fetch';
import WebSocket from 'ws';

// See fetch-odds.js for why these polyfills are needed on this machine's
// older Node version.
if (!globalThis.fetch) {
  globalThis.fetch = fetch;
  globalThis.Headers = Headers;
  globalThis.Request = Request;
  globalThis.Response = Response;
}
if (!globalThis.WebSocket) {
  globalThis.WebSocket = WebSocket;
}

const { createClient } = await import('@supabase/supabase-js');

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ODDS_API_KEY } = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !ODDS_API_KEY) {
  console.error('Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or ODDS_API_KEY -- check your .env file.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// daysFrom=3 asks for completed games from the last 3 days too (without
// it, the API only returns live/upcoming games, no finished ones).
const SCORES_URL =
  'https://api.the-odds-api.com/v4/sports/soccer_epl/scores/' +
  `?apiKey=${ODDS_API_KEY}&daysFrom=3`;

async function main() {
  const res = await fetch(SCORES_URL);
  if (!res.ok) {
    throw new Error(`The Odds API request failed: ${res.status} ${await res.text()}`);
  }
  const events = await res.json();

  const finished = events.filter((e) => e.completed && e.scores);
  console.log(`${finished.length} of ${events.length} fetched fixtures are finished.`);

  for (const event of finished) {
    const homeScore = scoreFor(event, event.home_team);
    const awayScore = scoreFor(event, event.away_team);
    if (homeScore === null || awayScore === null) continue; // scores array didn't match our team names, skip

    const { data, error } = await supabase
      .from('fixtures')
      .update({ home_score: homeScore, away_score: awayScore, status: 'finished' })
      .eq('external_id', event.id)
      .neq('status', 'finished') // don't re-trigger scoring for a fixture we already finished
      .select();

    if (error) {
      console.error(`Failed to update ${event.home_team} vs ${event.away_team}:`, error.message);
      continue;
    }
    if (data.length > 0) {
      console.log(`${event.home_team} ${homeScore} - ${awayScore} ${event.away_team} -- saved, predictions scored.`);
    }
  }
}

function scoreFor(event, teamName) {
  const entry = event.scores.find((s) => s.name === teamName);
  return entry ? Number(entry.score) : null;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
