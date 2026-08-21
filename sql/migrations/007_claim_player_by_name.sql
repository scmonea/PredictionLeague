-- Migration: lets a visitor "claim" an existing display name instead of
-- being blocked by the unique constraint when their session is lost (new
-- device, cleared browser storage, or an in-app browser -- e.g. tapping a
-- link inside WhatsApp/iMessage -- that doesn't persist local storage the
-- way a normal browser tab does). Matching is case-insensitive, so
-- "Josh" and "josh" are treated as the same player, not two separate
-- signups.
--
-- DELIBERATE TRADE-OFF, NOT A BUG: display names are public (visible on
-- the leaderboard), so this means ANYONE who knows a friend's name can
-- type it in (any case) and take over that identity -- submit or change
-- predictions as them, no password involved. Only reasonable for a
-- small, trusted friends group. If the group ever grows past people
-- you'd trust with each other's picks anyway, replace this with real
-- login instead.
--
-- Replaces the insert-then-catch-unique-violation flow that used to live
-- in ensurePlayer() (supabase-client.js) with one atomic RPC call: create
-- the player if the name is new, or reassign the existing row's
-- auth_user_id to the caller if the name is already taken (case-
-- insensitively). Runs as SECURITY DEFINER because `players` has no
-- UPDATE policy (see schema.sql) -- that's intentional, and this
-- function is the one sanctioned way around it.
--
-- The unique index below enforces case-insensitive uniqueness at the
-- database level too (not just inside this function), so a direct insert
-- from anywhere else can't create a case-variant duplicate either.
--
-- Safe to re-run.

create unique index if not exists players_display_name_ci_idx
  on players (lower(display_name));

create or replace function claim_player(p_display_name text)
returns players
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player players%rowtype;
begin
  select * into v_player from players where lower(display_name) = lower(p_display_name);

  if found then
    update players
    set auth_user_id = auth.uid()
    where id = v_player.id
    returning * into v_player;
  else
    insert into players (auth_user_id, display_name)
    values (auth.uid(), p_display_name)
    returning * into v_player;
  end if;

  return v_player;
end;
$$;

grant execute on function claim_player(text) to authenticated;
