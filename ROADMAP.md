# Knightly Roadmap

Knightly is a personal fork of the Lichess Mobile app, tweaked to support my own chess learning.

Status: `[ ]` planned · `[~]` in progress · `[x]` done

## Analysis board

- [x] Best move arrow toggle in the bottom bar (replaces the board size toggle)

## Live play (Board API)

Self-built apps can't use the official app's login on lichess.org (`web:mobile` tokens must be
signed with lichess's private key). Instead: standard lichess OAuth + the public Board API.

Allowed: Rapid, Classical, Correspondence everywhere; Blitz only vs a friend or the AI. No Bullet.
No engine/analysis help during live games (fair play: the account can be banned).

1. [x] Login with standard lichess OAuth (PKCE, own client id, normal scopes), Knightly user
   agent, websocket `sri`/`load` query params. The pending sign in is kept in secure storage, so it
   survives Android killing the app while the browser is open.
2. [ ] Play the lichess AI and challenge a friend (first end-to-end live play)
3. [ ] Lobby seeks (Rapid/Classical) and incoming/outgoing challenges
4. [ ] Correspondence games and the ongoing games list
5. [ ] Puzzles with my account (personal puzzle stream, saving results, dashboard)

Removed: Bullet and Blitz quick pairing tiles, inbox (menus, Home banner, unread badges), team
updates, Donate, About, the Watch tab, personal study lists (mine, favorites), tournaments (all
entry points; tournament links open in the browser).

Fixed: Home no longer uses the official-app-only `/api/mobile/home` (each request is made on its
own), the friends carousel uses the public `/api/rel/following`, finished games open in analysis
(the player socket rejects Knightly's token), user profiles are built from public endpoints
instead of `/api/mobile/profile` (no crosstable for now), and "Create a game" only allows Rapid and
slower time controls.

Tournaments: joining works and lichess pairs the games right away, so they stay blocked until live
play works (a paired game would be lost on time).

Not possible with the API (remove later): notifications list and timeline, push notifications,
saving settings to the account, saving Storm/Streak scores.

## Branding

- [ ] Rebrand the app to Knightly: app name on the home screen (currently "Lichess"), icon and
  splash screen, own Android application id instead of `org.lichess.mobileV2` (also needs its own
  Firebase config, or Firebase removed), and remove Lichess branding inside the app (Lichess logo
  and name are lichess's trademarks)

## Training

- [ ] Spaced repetition for failed puzzles: puzzles I fail come back for review at growing
  intervals until I solve them reliably

## Ideas

- [ ] ...

## Notes

- Run against the real site as a guest:
  `flutter run -d <device> --dart-define=LICHESS_HOST=lichess.org --dart-define=LICHESS_WS_HOST=socket.lichess.org`
- Logging in to lichess.org uses Knightly's own OAuth login (see step 1); use Firefox or Chrome as
  the default browser (Brave doesn't redirect back to the app).
- Add features in new files where possible, to keep merging upstream changes easy.
