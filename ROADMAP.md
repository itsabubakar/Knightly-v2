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

## UI rework (current)

Style inspired by ChessFlare's colors (not its artwork): the "Flare" theme.

- [x] Flare theme: dark by default, orange accent `#FE7201`, warm surfaces, rounder cards and bolder
  buttons (Android only; `lib/src/styles/knightly_theme.dart`)
- [x] Tabs: Home, Play, Train (puzzles + learn), Profile (account, tools, community)
- [ ] Home dashboard: streak, level and goals cards, continue (your turn, games to review), quick
  play; sections appear as their features are built
- [ ] Progress tab (5th): ratings, rating history, recent form, puzzle performance; later streak,
  XP, levels, disciplines, achievements, analytics, reports
- [ ] Polish: pressable cards, colored icon badges, bolder headings, quick pairing tiles, orange
  board theme, Home header, animations

## Phases

Order agreed on 2026-11-16: the UI rework first, then live play, then the training features. Each
phase ends with the app working on the phone and the tests passing.

### Phase 1: Live play

Steps 2 to 5 of "Live play (Board API)" above, then unblock tournaments (step 6).

6. [ ] Tournaments back, played through the Board API (test the pairing first)

### Phase 2: Foundation

- [ ] Local database tables for Knightly's own data (tags, XP, streak, study sessions, goals)
- [ ] Backup: export all Knightly data to a file and import it back (the data lives only on the
  phone: uninstalling or clearing the app's data loses it)
- [ ] Bug: "unable to fetch tournament data" on Home, seen only when the debug app is opened without
  `flutter run` attached (check in a profile or release build)
- [ ] Bug: profile screen shows "Retry" for a moment before the real data

### Phase 3: Streak

- [ ] Daily streak: a day counts when at least one game is finished, played anywhere (Knightly,
  official app, website), any speed, rated or casual, correspondence included; read from the
  lichess game history; days roll over at local midnight
- [ ] Streak freezes: forgive one missed day; earned from achievements and level ups, not bought

### Phase 4: Game tagging and review

- [ ] Tag moves of finished games (never during a live game: fair play)
- [ ] Tag list: an editable starter list plus my own tags
  - Mistakes: hanging piece, missed tactic, calculation error, time trouble, opening mistake,
    endgame technique, positional error
  - Good decisions: good move, good plan
- [ ] Tag suggestions: when the best move arrow is shown and the played move differs (or lichess's
  computer analysis marks a mistake or blunder), suggest tagging the move
- [ ] Game review: a "lessons learned" note per game
- [ ] Filter my games by tag

### Phase 5: Progression

- [ ] Player XP and levels (proposed XP table below, to adjust)
- [ ] Discipline levels: tactics, strategy, openings, endgames, analysis
  - puzzle themes count for tactics and endgames, study sessions for their category, tags for
    their area (e.g. "opening mistake" for openings), game reviews for analysis
- [ ] Achievements (some award streak freezes)

Proposed XP table:

| Activity | XP |
|---|---|
| Move tagged | 5 |
| Game reviewed (lessons note written) | 20 |
| Rapid game finished | 15 |
| Classical game finished | 25 |
| Correspondence game finished | 25 |
| Blitz game finished (vs friend or AI) | 5 |
| Puzzle solved | 2 |
| 10 minutes of study | 10 |
| Daily goal completed | 20 |
| Streak day | 5 (+1 per 7 days of streak, max 15) |

### Phase 6: Study tracker

- [ ] Stopwatch: start and stop while studying
- [ ] Countdown: set a duration (e.g. 20 minutes) and count down while using the app
- [ ] Manual entry: log a session afterwards
- [ ] Each session has a category (tactics, strategy, openings, endgames, analysis)

### Phase 7: Daily goals

- [ ] Set daily training activities (e.g. 1 rapid game, 10 puzzles, 20 minutes of endgames) and
  check them off automatically

### Phase 8: Weakness analytics

- [ ] Recurring mistakes from tags, and how they change over time

### Phase 9: Monthly reports

- [ ] Summary of the month: activity, quality (accuracy, mistakes per game), improvement

### UI enhancement

- [ ] Waiting for reference screenshots. Likely a Home dashboard (streak, level, today's goals),
  fitting with phases 3, 5 and 7. Keep all lichess features working.

## Training

- [ ] Spaced repetition for failed puzzles: puzzles I fail come back for review at growing
  intervals until I solve them reliably (could join phase 5 or 7)

## Ideas

- [ ] ...

## Notes

- Run against the real site as a guest:
  `flutter run -d <device> --dart-define=LICHESS_HOST=lichess.org --dart-define=LICHESS_WS_HOST=socket.lichess.org`
- Logging in to lichess.org uses Knightly's own OAuth login (see step 1); use Firefox or Chrome as
  the default browser (Brave doesn't redirect back to the app).
- Add features in new files where possible, to keep merging upstream changes easy.
