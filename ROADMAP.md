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

## Study time on the board (decided 2026-11-24; built, testing on the phone)

- [~] A clock under the board (bottom right, next to the player) on the analysis board and on
  lichess studies: it runs from when the screen opens and stops when it closes, nothing to start
  or stop; it doesn't count while the app is in the background. The time is saved as a study
  session (Analysis, or Openings with the study) when the screen closes, a minute or more, +1 XP a
  minute
- [~] The floating study timer, its start buttons (analysis menu, study menu, bookmarked studies)
  and the Study tracker's countdown and stopwatch are removed; the Study tracker keeps the
  sessions, "Log a past session", and a timer left running from before

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
- [ ] Not done yet (see Phase 7c): berserk, the game's sounds on low
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
- [~] Move confirmation in Knightly's game screen, following the "Move confirmation" setting for
  each kind of game (correspondence, unlimited, classical, rapid, blitz): the move shows on the
  board with cancel and confirm buttons; premoves aren't asked about

### Phase 7c: what lichess's game screen had (decided 2026-11-23)

What the old game screen did that Knightly's doesn't yet, and the Board API allows, in batches.

Batch 1, things that behaved like bugs (built, testing on the phone):

- [~] Auto-queen follows the "Promote to Queen automatically" setting (always, or on premoves)
- [~] Moves vibrate as the board settings' haptic feedback asks (stronger on a check)
- [~] The screen may sleep again once the game is over
- [~] No premoves in correspondence games
- [~] The user's own draw offer and takeback proposal can be cancelled
- [~] Resigning and offering a draw are confirmed as "Confirm resignation and draw offers" says

Batch 2, clock (built, testing on the phone):

- [~] The low-time sound, once when the user's clock goes under the threshold on their turn (account
  setting "Clock sound")
- [~] Tenths of a second (account setting)
- [~] The clock on the left or right (board setting)
- [~] The low-time threshold from the time control, as lichess's: an eighth of the initial time,
  between 10 seconds and a minute (was 20 seconds for every game)

Batch 3, sounds and feel (built, testing on the phone):

- [~] The confirmation sound when a move is confirmed
- [~] Atomic: its capture sound (with batch 1's move feedback) and the explosion; the explosion
  plays again when coming back to the live position from earlier moves (minor)
- [~] No piece animation in bullet
- [~] Sounds when going through the moves (previous, next, tapping a move, which also vibrates)

Batch 4, settings in the game (built, testing on the phone):

- [~] The game's settings icon opens a settings sheet: sound, move confirmation and auto-queen for
  this game (shown when the account's settings use them), zen mode, chat, blindfold, and the board
  settings
- [~] Zen mode hides the names, the material, the chat and the moves (the clocks stay); it follows
  the account's "Zen mode" (during games, or always), or the sheet for this game
- [~] Blindfold mode hides the pieces

Batch 5, end of game and draws (built, testing on the phone):

- [~] Claim a draw on threefold repetition (a button under the board; sent as a draw "yes", which
  lichess takes as the claim)
- [~] Claim a draw ("Call it a draw"), not only victory, when the opponent left
- [~] lichess's wording of the result, in the app's language, and who won
- [~] Tapping the result under the board opens the result popup again
- [~] New opponent (real-time games against a person): seeks again with the same time control,
  variant and rated or casual
- [~] The rating changes next to the ratings once lichess has them (rated games)

Batch 6, getting around and sharing (built, testing on the phone):

- [~] Next correspondence game where it's the user's turn: under the board once the user has moved,
  and in the More menu
- [~] Bookmark the game (More menu; lichess's bookmark, as the analysis screen does)
- [~] Share the link; once over, the PGN (annotated or raw) and a GIF (More menu)
- [~] The speed icon in the title; the last move time under the clocks in correspondence
- [~] "Reconnecting…" in the title while the game stream is opened again
- [~] Android full screen while playing a real-time game (board setting "Immersive mode")

Batch 7, player bar and tournaments (built, testing on the phone):

- [~] The head-to-head score next to each name (lichess's crosstable; games against people)
- [~] BOT title in lichess's colour; the patron wings and the flair, from the players' profiles
- [~] Berserk: the button in an arena that allows it, before the user's first move; the icon next
  to a berserk player, and the sound (the button needs the arena's details: not tested with a real
  one)
- [~] Back to the tournament (More menu, result popup); pause it once the game is over (More menu)
- [~] No chat in arena games, and no "New opponent" (the arena pairs)

Not possible with the Board API: giving the opponent time, flagging (lichess does it), the
spectators, the tournament rank, the forecasts badge.

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

## Training: openings and mistakes (decided 2026-11-23; built, testing on the phone)

**2026-11-24: the openings trainer is set aside**: only the mistakes are shown (Home's card "Your
mistakes", the "Your mistakes" screen). The repertoire screens, model and saved repertoires stay in
the code and the database, not reachable, to bring back later.

One review system with spaced repetition for two kinds of cards: a position of an opening
repertoire (play your prepared move) and a mistake from one of the user's games (find the move
missed).

- [~] Cards with a review schedule: right, the next review waits a day, then 3, then longer (times
  an ease that grows); wrong, it comes back in 10 minutes and starts over. At most 15 new cards a
  day
- [~] A session: the cards due, then the new ones; a wrong move shows the right one (an arrow),
  which the user plays, and the card comes back at the end; Skip. No moving on by itself: Next once
  answered. Previous and next (held: repeated) go through the moves that led to the position
- [~] A mistake shows the move played in the game and its evaluations (before, after: the loss),
  then once found the best move's evaluation and what it gains (database version 9; the recent
  games are looked through again to fill them in for the puzzles made before)
- [~] +1 XP per card right, once a day (Openings or Tactics); a day of training keeps the streak
- [~] Openings and mistakes apart: Home's Training card has a line for each with its count and
  Train (a single line when nothing is due); the Training screen behind it has an Openings section
  (the repertoires, Train openings) and a Mistakes section (Train mistakes, the games the puzzles
  come from, each with its own training, and "Look for mistakes now")
- [~] Repertoires, as White or Black: built on a board; the user's move in each of their positions
  (lichess's most played moves suggested, with their share), and the opponent's 3 most played
  replies (at the levels and speeds of the opening explorer settings) added on their own down to
  move 10; "Add top replies", a To do list of the positions waiting for the user's move, remove a
  move (and what came after it), train one repertoire
- [~] Mistake puzzles: the user's mistakes and blunders with one clear answer (the engine's best
  move at least 0.2 winning chances better than the second best, checked for 1 second with 2
  lines). From each game Knightly analyses (when its deep pass ends), and from the user's recent
  games (rapid and slower, last 30 days), 3 at a time, a few seconds after Home opens (once per
  session), with a quick analysis made then and saved for the analysis board
- [ ] Not yet: import a PGN or a lichess study into a repertoire; repertoire coverage of the user's
  games; puzzles from lichess's own analysis of a game

## Ideas from ChessFlare (noted 2026-11-23)

Features of ChessFlare: Chess Training 1.1.13 (Anakyos Apps), read from the translation keys in its
app bundle. Ideas only: none of its code, text or images. Marked: **have** (Knightly has it),
**partial**, **new**; and what it would need.

Training plan and habits

- [ ] Routine builder (**partial**: Phase 8 daily goals): a weekly plan, missions per weekday
  (puzzles by theme, an opening trainer, a course, a bot game, a review of the latest loss,
  Woodpecker cycles), reminders
- [ ] Weekly quests and a weekly summary "story" to share (**new**)
- [ ] A streak challenge with a bonus (**partial**: Knightly's streak already has freezes)
- [ ] Home "guided" plan: analyse your latest loss, review a game, today's missions (**partial**:
  Phase 9 review queue)

Puzzles and tactics

- [~] Puzzles made from the user's own mistakes: built (see Training below)
- [ ] Woodpecker method: the same puzzle set in cycles, faster each time, with time and accuracy per
  cycle (**new**; lichess puzzles by theme)
- [ ] Puzzle sprint (**partial**: lichess Puzzle Storm and Streak)
- [ ] The tactic shown on the board: fork, pin, skewer, battery, overloaded, hanging, trapped,
  discovered, back rank (**new**)

Openings

- [~] Repertoire builder and trainer with spaced repetition: built (see Training below)
- [ ] Repertoire coverage: which of the user's games left the repertoire, lines to add, "this move
  isn't in your repertoire yet" (**new**)

Courses

- [ ] Courses: chapters, a learn mode with spaced review, a mastery chart, course search (**partial**:
  lichess studies, Learn)
- [ ] Endgame path: opposition, the rule of the square, breakthrough, triangulation, rook activity
  (**partial**: lichess practice)

After a game

- [ ] Post-game report: a radar of opening, tactics, endgame and precision, compared with players
  of the same rating, with exercises and a course for the weakest (**partial**: accuracy and game
  insights; no comparison with others)
- [ ] Key moments of a game (**partial**: local analysis finds the mistakes)

Play

- [ ] Bots with personalities and human-like play (Maia) (**partial**: lichess AI, Maia exists as
  lichess bots)
- [ ] Board scanner: a photo of a board to a position (**new**; needs on-device recognition)

Progress and social

- [ ] Skill graph across areas (**partial**: Phase 9 discipline levels)
- [ ] Badges with rarity (**partial**: achievements)
- [ ] Monthly and all-time leaderboards, friends, invitations by QR code (**new**; no server)
- [ ] Rating chart per time control "since the last review" (**partial**)
- [ ] Chess.com games imported too (**new**; chess.com's public API)

AI coach

- [ ] A coach to chat with, which sees the user's games, mistakes and stats, attaches positions and
  photos, and recommends exercises (**new**; needs an AI service)

Not for Knightly: crowns, energy and the paywall (ChessFlare's paid model), cosmetics to unlock.

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
