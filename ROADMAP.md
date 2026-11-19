# Knightly Roadmap

Knightly is a personal fork of the Lichess Mobile app, tweaked to support my own chess learning.
Android only.

Status: `[ ]` planned · `[~]` in progress · `[x]` done. Each phase ends with the app working on
the phone and the tests passing.

## Overview

| Phase | What | Status |
|---|---|---|
| 0 | Setup: login, fixes, removals, UI rework | done (UI polish left for phase 9) |
| 1 | Foundation: Knightly database and backup | done |
| 2 | XP, levels and titles | done |
| 3 | Achievements | done |
| 4 | Streak | done |
| 5 | Move tagging and game review | done |
| 6 | Study tracker | done |
| 7 | Live play (Board API) | **built, testing on the phone** |
| 8 | Daily goals | planned |
| 9 | Later: disciplines, analytics, reports, polish (rebranding done) | planned |

## Phase 0: Setup

### Login and lichess fixes

- [x] Login with standard lichess OAuth (PKCE, own client id `knightly`, normal scopes), `Knightly/`
  user agent, websocket `sri`/`load` query params; the pending sign in is kept in secure storage,
  so it survives Android killing the app while the browser is open
- [x] Home doesn't use the official-app-only `/api/mobile/home` (each request is made on its own);
  the friends carousel uses the public `/api/rel/following`; finished games open in analysis;
  user profiles come from public endpoints (no crosstable for now)
- [x] Account preferences changed in Knightly are kept on the phone (lichess rejects third-party
  preference writes)
- [x] Study bookmarks on the phone replace lichess's study likes (latest 3 on Home, all in Train)
- [x] Best move arrow toggle in the analysis bottom bar

### Removed (not possible with the API, or not wanted)

- [x] Bullet and Blitz in the lobby (quick pairing and "Create a game": Rapid and slower only)
- [x] Inbox, team updates, Donate, About, the Watch tab, personal study lists
- [x] Tournaments until phase 7 (back in phase 7, Rapid and Classical only)

### UI rework

- [x] Flare theme: dark by default, orange accent `#FE7201`, warm surfaces, rounder cards, bolder
  buttons (inspired by ChessFlare's colors, not its artwork)
- [x] Tabs: Home, Play, Train (puzzles and learn), Progress, Profile
- [x] Home: Today card (games today, results, Rapid rating, streak, level), ongoing games, quick
  play, bookmarked studies
- [x] Progress: journey card, achievements, game review, ratings, rating history,
  puzzle performance

## Phase 1: Foundation

- [x] Knightly's own database `knightly.db` (separate from lichess's), versioned migrations
- [x] Backup & restore (Profile): export a JSON file through the share sheet, restore from a file,
  automatic weekly backup (4 kept) in the app's folder; covers `knightly.db` and the `knightly.*`
  settings

## Phase 2: XP, levels and titles

- [x] XP counts from the first sign in to Knightly (not the past), synced from lichess, each
  activity counted once (see the XP table below)
- [x] Levels: level 2 at 100 XP, each next level needs 25 XP more; titles from The Newcomer to The
  Grandmaster; Roman numerals
- [x] "Your chess journey" card on Progress; level strip and XP today on Home

## Phase 3: Achievements

- [x] 20 achievements (games, puzzles, levels, streak, review, study), each earned once, with XP
  and streak freezes; a freeze per level-up; at most 3 freezes held
- [x] Achievements grid on Progress; celebration popup for level-ups and achievements, shown once

## Phase 4: Streak

- [x] A day counts when a game was finished (any speed, rated or casual, correspondence included);
  a missed day uses a freeze automatically; today doesn't break the streak until it's over
- [x] Missed days are settled only after a successful sync (never offline)
- [x] Streak and 7-day strip on Home and Progress; streak achievements live

## Phase 5: Move tagging and game review

- [x] Tag button in the analysis bottom bar, for the moves of the user's own finished games (never
  live): mistakes and good decisions
- [x] Suggestion when lichess's computer analysis marks the move as an inaccuracy, mistake or
  blunder
- [x] Engine suggestion without server analysis: the analysis board's engine (local or cloud)
  compares the positions before and after the move (practice mode thresholds), with the best move;
  "Check with engine" evaluates the position before the move when needed
- [x] Reviewed games filter by period: all time, 7, 14, 30 days, or a custom date range
- [x] Game insights on Progress (7, 30, 90 days or custom): games reviewed, games with mistakes,
  time trouble games, strong games, most frequent tags
- [x] Editable tag list (starter tags plus your own; rename, remove, restore)
- [x] "Lessons learned" note per game from the analysis menu
- [x] Reviewed games screen, filterable by tag; Game review card on Progress; review achievements
  live

## Phase 6: Study tracker

- [x] Stopwatch and countdown (10 to 60 minutes), with pause; the timer survives the app being
  closed; a countdown ends on its own ("Session complete"); a stopwatch counts at most 3 hours
- [x] A timer pill floats above every screen while a session runs (pause, stop, open)
- [x] Start a timer (countdown or stopwatch) from a bookmarked study (its timer button) or a
  study's menu: the session keeps the study, shown on the pill, the timer and the sessions
- [x] Manual entry: log a past session (category, minutes, date)
- [x] Each session has a category (tactics, strategy, openings, endgames, analysis); sessions list
  with delete; Study timer in Train
- [x] Study time and sessions on the journey card; 1 XP per minute (under a minute doesn't count);
  "Deep Focus" achievement live

## Phase 7: Live play (Board API)

Allowed: Rapid, Classical, Correspondence everywhere; Blitz only vs a friend or the AI. No Bullet.
No engine or analysis help during live games (fair play: the account can be banned).

How it works: the user's event stream (`/api/stream/event`) announces game starts and
challenges; each game is followed through its game stream (`/api/board/game/stream/<id>`) and
moves are sent with `POST /api/board/game/<id>/move/<uci>`. The game screen is Knightly's own
(`BoardGameView`); lichess's websocket game code stays for upstream's tests.

- [~] Play the lichess AI (Play tab: level 1 to 8, Blitz to Classical, color) and challenge a
  friend (the challenge is kept alive until accepted or declined)
- [~] Lobby seeks (quick pairing, "Create a game"; Rapid and Classical) and incoming challenges
  (notification, accept or decline)
- [~] Correspondence games and the ongoing games list (open in the Board API game screen)
- [ ] Puzzles with my account (personal puzzle stream, saving results): check on the phone first
- [~] Tournaments back (Play tab and links), Rapid and Classical only: joining, then each pairing
  opens on its own
- [~] A live game that starts or is going on opens on its own (seek pairing, accepted challenge,
  tournament pairing, a game left open when the app closed)
- [ ] Not done yet: premoves, chat, berserk, rematch, move confirmation, the game's sounds on low
  time; cancelling a correspondence seek (uses the websocket)

### Phase 7b: game screen and analysis (decided 2026-11-18; built, testing on the phone)

- [~] Takebacks follow the "Takeback" setting: no button when set to never (or in rated games when
  casual only); the opponent's proposals are then declined on their own (lichess still has the
  account's old setting: Knightly can't change it)
- [~] Holding previous or next move goes through the moves
- [~] Inbox and every message action open lichess.org in the browser (the API can't read the inbox)
- [~] Rematch offers (they come as challenges) shown in the game: a bar under the board for a
  rematch of this game (accept, decline), a challenges icon with a count for the others
- [~] Chat in every game: icon with an unread badge, a sheet with the messages, lichess's quick
  phrases; off in kid mode
- [~] The end of game popup leads with the XP: what the game gave and why, the level bar, the
  streak, a level up; the XP counts at once (the sync later doesn't count it twice)
- [~] Comments on moves (long press, "Comment"), only for games (finished, and correspondence
  games going on): saved on the phone with the side lines, in the copied PGN; separate from the
  computer analysis comments
- [~] Knightly's computer analysis instead of lichess's "Request a computer analysis" (only the
  official app can ask for it): a quick pass at once, then a deep one in the background that
  refines it; inaccuracy, mistake, blunder (with the best line and lichess's comments), the
  graph, accuracy; saved on the phone; any game. lichess's own analysis shows when it exists.
  "Learn from your mistakes" works from it
- [~] The debug build has its own sign in link (`app.knightly.debug`), so it can't take the
  release app's sign in

Fixes after the first phone test (2026-11-19):

- [~] The tag move sheet has two tabs, Tag and Comment, so a tagged move gets its comment there
- [~] The user's comments are apart from the computer's in the move list (italics, a pen before
  them), with their own switch in the analysis settings ("Show my comments"); "Show computer
  comments" no longer hides them
- [~] The background analysis no longer fights the analysis board's engine (they share one
  Stockfish): it waits while the user's engine is evaluating, and goes again over a position the
  user interrupted; it shows its progress every second (quick pass) or five (deep pass) rather
  than after every position, each update rebuilding the move list; a position the engine is done
  with early (a mate) isn't waited on until the timeout
- [~] No more correspondence sync with lichess's mobile endpoints (403 "Missing scope" in the logs):
  the Board API keeps no offline games
- [~] A study timer for analysis sessions: "Start study timer" in the analysis board's menu,
  Analysis as the category

## Phase 8: Daily goals

- [ ] Set daily training activities (e.g. 1 Rapid game, 10 puzzles, 20 minutes of endgames),
  checked off automatically
- [ ] "Today's progress" on Home and Progress; XP per goal completed

## Phase 9: Later

- [ ] Discipline levels: tactics, strategy, openings, endgames, analysis (the XP is already
  recorded per discipline)
- [ ] Weakness analytics: recurring mistakes from tags, and how they change over time
- [ ] Monthly reports: activity, quality (accuracy, mistakes per game), improvement
- [ ] Home review queue: games waiting to be reviewed
- [ ] Spaced repetition for failed puzzles
- [ ] UI polish: pressable cards, colored icon badges, bolder headings, quick pairing tiles, orange
  board theme, animations
- [x] Rebranding: app name "Knightly", launcher icon (v1's black knight on gold, themed icon
  layer), splash (brass knight on Flare dark), notification icon, own application id
  `app.knightly` (installs next to the official Lichess app), Firebase removed (no push: lichess
  only pushes to its own app; local notifications still work), no "Rate this app"; a Knightly
  line replaces lichess's "free, libre, open source chess server" message (Home and Profile).
  "Lichess" stays where it names the service (sign in, opening explorer, server outage)
- [ ] Bug: "unable to fetch tournament data" on Home, seen only when the debug app runs without
  `flutter run` attached (check in a release build)
- [ ] Bug: the profile screen shows "Retry" for a moment before the real data

## Reference

### XP table

| Activity | XP |
|---|---|
| Rapid game finished | 15 |
| Classical or Correspondence game finished | 25 |
| Blitz game finished | 5 |
| Bullet or UltraBullet game finished | 0 |
| Game length (from phase 7b, new games only) | the game's XP is ×0 under 10 moves, grows to ×1 at 30 moves and ×1.5 at 60 (max); win, draw and loss alike |
| Puzzle solved | 2 |
| Move tagged | 5 |
| Game reviewed (lessons learned note) | 20 |
| Streak day | 5, +1 per 7 days of streak, max 15 |
| 10 minutes of study (phase 6) | 10 |
| Daily goal completed (phase 8) | 20 |
| Achievement | its own XP |

### Lichess API limits

- Self-built apps can't use the official app's login on lichess.org: `web:mobile` tokens must be
  signed with lichess's private key, and the websocket server only accepts those. Knightly uses
  standard OAuth and the public API instead.
- Not possible with the public API: reading the inbox, notifications and timeline, push
  notifications, saving account preferences, saving Storm and Streak scores, Bullet, Blitz in the
  lobby.

## Notes

- Run against the real site:
  `flutter run -d <device> --dart-define=LICHESS_HOST=lichess.org --dart-define=LICHESS_WS_HOST=socket.lichess.org`
- Use Firefox or Chrome as the default browser for the login (Brave doesn't redirect back).
- After a phase, restart the app fully (`R` in `flutter run`, or `q` then `flutter run`): a hot
  reload doesn't upgrade Knightly's database.
- Add features in new files where possible, to keep merging upstream changes easy.
