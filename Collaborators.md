# Git Collaboration & Workflow Guide
## Assembly Language Project (WSL2 / Ubuntu / Linux)

Welcome to the team! Because we are writing Assembly language in a Linux/WSL2 environment, keeping our Git repository clean is critical. Assembly projects generate machine-specific binary files (`.o`, executables, etc.) that will cause severe merge conflicts if tracked. This guide covers how we keep those files out of the repo in the first place, along with our branch protections and daily development loop, using **GitHub CLI** for web authentication.

**Read this entire document before writing any code.**

---

### Part 1. Install and Authenticate via Web Browser (GitHub CLI)

Instead of dealing with SSH keys or Personal Access Tokens, we use the official GitHub CLI to log in and use it to authenticate `git` operations automatically.

#### Step A: Install GitHub CLI (`gh`)

In your Ubuntu/WSL2 terminal, run:

```bash
sudo apt update
sudo apt install gh -y
```

#### Step B: Run the Web Login Command

```bash
gh auth login
```

#### Step C: Answer the Prompts

1. **What account do you want to log into?** → `GitHub.com`
2. **What is your preferred protocol for Git operations?** → `HTTPS`
3. **Authenticate Git with your GitHub credentials?** → `Y` *(this makes Git automatically use this login for `git push`/`pull`)*
4. **How would you like to authenticate GitHub CLI?** → `Login with a web browser`

#### Step D: Complete Browser Activation

1. The terminal outputs a **one-time 8-character code** (e.g., `XXXX-XXXX`). Copy it.
2. Press **Enter**. It attempts to open your default browser. If it doesn't, manually go to **https://github.com/login/device**.
3. Paste your code, click **Continue**, authorize the login.
4. The terminal confirms `✓ Authentication complete`.

---

## Part 2: First-Time Setup (Do Once)

### 1. Configure Your Git Identity

```bash
git config --global user.name "Your Real Name"
git config --global user.email "your-github-email@example.com"
```

### 2. Clone the Repository

The team repo already exists. Clone it with `gh`:

```bash
gh repo clone https://github.com/Khobbygriff/maze-game-asm
cd maze-game-asm
```

### 3. Create the `.gitignore` — Before Your First Commit

This is the actual fix for the binary-tracking problem described at the top of this doc. Do this **before** running `git add .` for the first time:

```bash
echo -e "*.o\nMaze_game" > .gitignore
cat .gitignore   # confirm it looks right
```

Should show:
```
*.o
Maze_game
```

Then confirm it's working before you commit anything:

```bash
git status
```

You should see your `.asm` files, `Build.sh`, and `README.md` listed as new files — but **not** `Maze_game` or any `.o` files. If you do see them listed, stop and check you're in the right directory and the `.gitignore` doesn't have a typo, before committing.

**If someone already committed a binary by accident** (this can happen if `.gitignore` was added after the first commit rather than before), adding it to `.gitignore` now will NOT remove it from tracking — Git only ignores *untracked* files. Fix it with:

```bash
git rm --cached Maze_game
git rm --cached *.o
git commit -m "Stop tracking build artifacts"
git push
```

Everyone else on the team should then `git pull` to pick up the removal.

---

## Part 3: The Core Workflow (Every Time You Code)

Our `main` branch is protected — a branch protection rule requiring pull requests is already configured in the repo's GitHub settings, so a direct `git push` to `main` will be rejected by GitHub itself, not just discouraged by convention. You **cannot** push directly to `main`. You must follow these 5 steps for every single change you make.

```
[Remote main] ──(Pull)──> [Local main] ──(Branch)──> [Local Feature] ──(Push)──> [Pull Request] ──(Merge)──> [Remote main]
```

### Step 1: Update Your Local Code

```bash
git checkout main
git pull origin main
```

### Step 2: Create a Feature Branch

```bash
git checkout -b feature/implement-player-movement
```

*Never write code while on the `main` branch.*

### Step 3: Write, Assemble, and Test

```bash
nasm -f elf64 player.asm -o player.o
ld player.o -o play_game
./play_game
```

### Step 4: Stage and Commit ONLY Source Files

Do **NOT** commit compiled binaries (`.o`, `.out`, or executables). With the `.gitignore` from Part 2 in place, `git add .` will already skip them automatically — but it's still worth checking `git status` before committing, especially the first few times, until you trust the habit.

```bash
git status
git add player.asm
git commit -m "Added keyboard input handling subroutine in player.asm"
```

### Step 5: Push Your Branch to GitHub

```bash
git push origin feature/implement-player-movement
```

*(Because of the GitHub CLI setup, this authorizes automatically — no password/token prompt.)*

---

## Part 4: Merging Your Code (Pull Requests)

1. Open the repo on [GitHub](https://github.com/Khobbygriff/maze-game-asm).
2. Click the **"Compare & pull request"** banner.
3. Write a brief description of what your code does and any dependencies.
4. Click **Create pull request**.
5. **Request a Review:** at least one classmate must review and approve.
6. Once approved, click **Merge pull request**.

---

## Part 5: Common Git Emergencies & Fixes

### Scenario A: "I accidentally started writing code directly on the `main` branch!"

**Do NOT commit yet.**

```bash
git checkout -b feature/my-new-branch
```

Git carries your uncommitted changes to the new branch, leaving `main` clean.

### Scenario B: "Git is showing merge conflicts!"

This happens when two people edit the same lines of the same file.

1. Open the conflicting file in your editor.
2. Look for the conflict markers:
```text
<<<<<<< HEAD
; Your local changes
MOV RAX, 1
=======
; Changes from the server
MOV RAX, 5
>>>>>>> origin/main
```
3. Manually delete the markers (`<<<<<<<`, `=======`, `>>>>>>>`) and keep the correct assembly code block.
4. Save the file, `git add <file>`, then `git commit` to resolve the conflict.

### Scenario C: "I already committed the compiled binary before we had a `.gitignore`."

See the fix in Part 2, Step 3 — `git rm --cached` on the tracked binary, commit, push, and have the rest of the team pull.

---

For a visual step-by-step setup walkthrough of the terminal installation process, you can watch this video on [How to install Git and run gh auth login](https://www.youtube.com/watch?v=gK5NrnWg150) to see how the interactive prompts look in real-time.