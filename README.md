# ASM Maze Escape

A terminal-based maze game written entirely in **x86-64 assembly** for Linux — no C library, no libc calls. Every piece of I/O (reading keys, drawing colored text, positioning the cursor, managing raw terminal mode) is done via direct Linux syscalls.

## Overview

You control `@`, navigating from a starting position to the exit tile (`E`) in each of three mazes. Along the way you can pick up coins and gems for bonus points, and finishing a level faster (fewer moves) earns a bigger completion bonus. There are three levels of increasing size and difficulty, all guaranteed solvable (see [How the mazes are built](#how-the-mazes-are-built)).

This project exists to demonstrate low-level systems programming: manual register management, the x86-64 calling convention, raw Linux syscalls (`read`, `write`, `ioctl`), and ANSI terminal control — all without any runtime or standard library support.

### What's implemented

- Three hand-verified, guaranteed-solvable maze levels with increasing difficulty
- Real-time keyboard input (raw terminal mode — no need to press Enter)
- Collectibles: coins (+10 pts) and gems (+25 pts) placed on tiles that are provably reachable
- Move-efficiency scoring: a level-completion bonus that shrinks the more moves you take
- Color-coded terminal output (blue walls, yellow player, green exit, colored collectibles)
- Player name entry, splash screen, and an in-game help screen
- Clean terminal teardown on exit (your shell is restored to normal, even if you quit mid-maze)

### Deliberately left out

- **No timer.** Input is read via a blocking `read()` syscall, so there's no way to measure real elapsed time without introducing threads or signal-based polling — implementing a timer that only "ticks" between keypresses would be misleading rather than genuinely real-time.
- **No lives/death.** There's currently no hazard or enemy that can kill the player, so a "lives" counter would just be an unused number on the HUD. Left out rather than shipped as a decoration.

## How it works (architecture)

The project is split into single-responsibility modules, each assembled separately and linked together:

| File | Responsibility |
|---|---|
| `Main.asm` | Program entry point (`_start`). Orchestrates the overall flow: name entry → splash/help → per-level game loop → win/score screens → clean exit. Owns the HUD drawing. |
| `Maze.asm` | Stores the raw maze data for all three levels, renders the maze to the screen, and answers "what tile is at (row, col)?" for collision checks. |
| `Player.asm` | Tracks the player's position, draws/erases the `@` glyph, and handles movement + wall-collision logic for WASD input. |
| `Game.asm` | Tracks overall game/session state: current level, win condition, move counter, score, and the collectibles system (placement, collection, scoring). |
| `Input.asm` | Reads raw keypresses (`read_key`) and full lines of text (`read_line`, used only for the name prompt before raw mode is enabled). |
| `Terminal.asm` | Low-level terminal control: clearing the screen, moving the cursor (ANSI escape codes), setting text color, and switching the terminal in/out of raw mode via `ioctl`. |
| `Utils.asm` | Shared helper: `int_to_string`, used anywhere a number (score, moves, level) needs to be printed. |

**Data flow, roughly:** `Main.asm` drives a loop that calls `Input.asm` for a keypress, `Player.asm` to attempt the move (which checks `Maze.asm` for wall collisions), `Game.asm` to check for a win or a collectible pickup, and `Terminal.asm`/`Maze.asm` to redraw the screen — repeating until the player reaches `E` or presses ESC.

### How the mazes are built

Each maze is generated offline using a randomized depth-first "carve" algorithm, then verified solvable with a breadth-first search (BFS) from the start tile to the exit before being hand-transcribed into `Maze.asm`. This guarantees every level can actually be completed and that every row has a consistent width (mismatched row lengths would silently corrupt tile lookups, since tile indexing is `row * width + column`).

Collectible placement follows the same discipline: coordinates are chosen from tiles that are both BFS-reachable *and* have at least two open neighbors, so an item never ends up visually embedded in a wall.

## Requirements

- **OS:** Linux (developed and tested on WSL2 / Ubuntu). The code relies on Linux-specific syscall numbers and `ioctl` structures, so it will not run on macOS or Windows natively.
- **Assembler:** [NASM](https://www.nasm.us/) (Netwide Assembler)
- **Linker:** GNU `ld` (part of `binutils`)

Install both on Ubuntu/WSL2 with:

```bash
sudo apt update
sudo apt install nasm binutils
```

## Build & Run

Clone or copy the project files into one directory, then from that directory:

```bash
chmod +x Build.sh
./Build.sh
./Maze_game
```

`Build.sh` assembles every `.asm` file in the directory into an ELF64 object file (`nasm -f elf64 -g -F dwarf`), then links them all into a single executable called `Maze_game`. The `-g -F dwarf` flags include debug symbols, which makes the binary steppable in `gdb` if you want to inspect it.

If you'd rather build manually:

```bash
nasm -f elf64 -g -F dwarf Main.asm -o Main.o
nasm -f elf64 -g -F dwarf Maze.asm -o Maze.o
nasm -f elf64 -g -F dwarf Player.asm -o Player.o
nasm -f elf64 -g -F dwarf Game.asm -o Game.o
nasm -f elf64 -g -F dwarf Input.asm -o Input.o
nasm -f elf64 -g -F dwarf Terminal.asm -o Terminal.o
nasm -f elf64 -g -F dwarf Utils.asm -o Utils.o
ld -o Maze_game Main.o Maze.o Player.o Game.o Input.o Terminal.o Utils.o
./Maze_game
```

## How to Play

1. On launch, enter your name and press Enter.
2. At the splash screen, press any key to start, or **H** for the help screen.
3. Move with:
   - `W` — up
   - `A` — left
   - `S` — down
   - `D` — right
4. Walk into a coin (`o`, yellow) or gem (`*`, cyan) to collect it automatically — coins are worth 10 points, gems are worth 25.
5. Reach the green `E` tile to complete the level. Your bonus for that level starts at 1000 points and decreases by 5 per move taken (with a floor of 100), so fewer moves = higher bonus.
6. After the third level, your final cumulative score is shown.
7. Press **ESC** at any time to quit immediately — the terminal is always restored to normal (non-raw) mode before the program exits, even if you quit mid-maze.

## Known Limitations & Possible Future Work

- No timer or "par time" scoring — see [Deliberately left out](#deliberately-left-out) for why.
- No lives, hazards, or enemies — currently no way to fail a level other than quitting.
- Levels are fixed and hand-transcribed into the binary; there's no random maze generation at runtime (the DFS-carve generator that produced these mazes is an offline tool, not part of the game itself).
- No persistent high-score file — scores reset when the program exits.
- Terminal size isn't checked; on a very small terminal window, level 3's 39×17 maze plus HUD rows may not fully fit on screen.

Natural next steps for anyone extending this: runtime maze generation, a save/high-score file (via the `open`/`write` syscalls), or a simple hazard system now that the collectibles infrastructure (a separate coordinate table + BFS-verified placement) already exists as a template for adding new per-tile entities.

## Author & License

Written as an assembly language course project. No external license is specified — treat as all-rights-reserved by the author unless you're told otherwise by whoever's distributing this copy.
