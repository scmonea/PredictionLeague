// Shared Supabase setup, loaded on every page (after the Supabase SDK
// itself) via:
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
//   <script src="supabase-client.js"></script>
//
// Sets up window.db (the Supabase client) plus a couple of helpers every
// page reuses: signing in anonymously, and "claiming" a display name the
// first time someone visits.

// These two values are safe to be public -- SUPABASE_URL and the "anon"
// key are designed to be used directly in browser code. All the real
// security lives in the Row Level Security policies in sql/schema.sql,
// not in keeping this key secret.
const SUPABASE_URL = 'https://xedoqpsjkfyaqttwrbxe.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_9IlBYt8UKOdXAilvTWcbhg_C2Bz8EZ7';

const db = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.db = db;

// Makes sure the visitor has an anonymous Supabase session -- creates one
// on first visit, reuses it on later visits (the session lives in the
// browser's local storage).
async function ensureSignedIn() {
  const { data: { session } } = await db.auth.getSession();
  if (session) return session;

  const { data, error } = await db.auth.signInAnonymously();
  if (error) throw error;
  return data.session;
}

// Returns the current visitor's row from the `players` table, prompting
// them to pick a display name the first time. Using a plain prompt() here
// is a deliberate simplification for a friends-only test -- swap it for a
// proper form later if this grows beyond messing around with mates.
//
// If they type a name that's already taken (e.g. because their previous
// session was lost -- new device, cleared storage, an in-app browser that
// doesn't persist local storage), claim_player() reassigns that existing
// player row to this session instead of blocking them. There's no
// password check, so this only works because it's a small trusted group
// -- see sql/migrations/007_claim_player_by_name.sql for the full
// trade-off.
async function ensurePlayer() {
  const session = await ensureSignedIn();

  const { data: existing } = await db
    .from('players')
    .select('*')
    .eq('auth_user_id', session.user.id)
    .maybeSingle();

  if (existing) return existing;

  let displayName = null;
  while (!displayName) {
    displayName = (prompt('Pick a display name for the league:') || '').trim();
  }

  const { data: claimed, error } = await db.rpc('claim_player', {
    p_display_name: displayName,
  });

  if (error) {
    alert(`Couldn't use that name (${error.message}). Try again.`);
    return ensurePlayer();
  }

  return claimed;
}

window.ensurePlayer = ensurePlayer;

// Display names are free text someone types in, so they must never be
// dropped straight into innerHTML -- this turns "<" etc into safe text.
function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

window.escapeHtml = escapeHtml;

// Registers the service worker so the site can be added to a phone's home
// screen and reload instantly / work mostly offline. Safe to no-op if the
// browser doesn't support it.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('service-worker.js');
}
