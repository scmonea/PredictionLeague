// Fetches upcoming Premier League fixtures + odds from The Odds API and
// saves them into the Supabase `fixtures` table. Run this by hand before
// each gameweek:
//
//   npm run fetch-odds
//
// This script runs on your computer via `node`, never in the browser --
// that's what keeps ODDS_API_KEY and SUPABASE_SERVICE_ROLE_KEY secret.
// The service_role key deliberately bypasses Row Level Security: this
// script is the only thing allowed to write to the `fixtures` table.
//
// Note: this only fetches upcoming fixtures + odds. Final scores are
// entered by hand in the Supabase Table Editor for now (see README) --
// that's what flips a fixture to 'finished' and triggers scoring.

import 'dotenv/config';
import fetch, { Headers, Request, Response } from 'node-fetch';
import WebSocket from 'ws';

// The Supabase client needs a few browser-standard globals (fetch,
// Headers, Request, Response, WebSocket) that are only built into
// Node 18+/22+. This machine has an older Node, so we polyfill them from
// node-fetch and ws before importing supabase-js (which grabs these off
// the global object as soon as it loads). We don't actually use realtime
// features here -- WebSocket just needs to exist so the client can
// construct itself without crashing.
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

const ODDS_URL =
  'https://api.the-odds-api.com/v4/sports/soccer_epl/odds/' +
  `?apiKey=${ODDS_API_KEY}&regions=uk&markets=h2h&oddsFormat=decimal`;

async function main() {
  const res = await fetch(ODDS_URL);
  if (!res.ok) {
    throw new Error(`The Odds API request failed: ${res.status} ${await res.text()}`);
  }
  const events = await res.json();
  console.log(`Fetched ${events.length} upcoming EPL fixtures from The Odds API.`);

  const rows = events.map(eventToFixtureRow).filter(Boolean);

  // Logged so a run that skips a fixture is visible in the Actions log,
  // not silent -- this workflow re-runs a few times a week (see
  // fetch-odds.yml), so a fixture skipped here should get picked up by a
  // later run once its odds are posted.
  const skipped = events.filter((e) => !eventToFixtureRow(e));
  if (skipped.length > 0) {
    console.log(`Skipped ${skipped.length} fixture(s) with no bookmaker odds yet: ${skipped.map((e) => `${e.home_team} vs ${e.away_team}`).join(', ')}`);
  }

  if (rows.length === 0) {
    console.log('Nothing to save -- none of the fetched events had bookmaker odds yet.');
    return;
  }

  // Upsert on external_id: re-running this script updates existing
  // fixtures with fresh odds instead of creating duplicates.
  const { error } = await supabase.from('fixtures').upsert(rows, { onConflict: 'external_id' });
  if (error) throw error;

  console.log(`Saved ${rows.length} fixtures to Supabase.`);
}

// Turns one event from The Odds API's response into a row matching our
// `fixtures` table. Returns null if the event has no bookmaker odds yet
// (happens for fixtures far in the future).
function eventToFixtureRow(event) {
  const bookmaker = event.bookmakers?.[0];
  const market = bookmaker?.markets?.find((m) => m.key === 'h2h');
  if (!market) return null;

  const priceFor = (teamName) => market.outcomes.find((o) => o.name === teamName)?.price ?? null;

  return {
    external_id: event.id,
    home_team: event.home_team,
    away_team: event.away_team,
    kickoff_at: event.commence_time,
    odds_home: priceFor(event.home_team),
    odds_draw: priceFor('Draw'),
    odds_away: priceFor(event.away_team),
    odds_fetched_at: new Date().toISOString(),
  };
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
