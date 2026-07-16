# Git Collaboration & Workflow Guide
## Assembly Language Project (WSL2 / Ubuntu / Linux)

Welcome to the team! Because we are writing Assembly language in a Linux/WSL2 environment, keeping our Git repository clean is critical. Assembly projects generate machine-specific binary files (`.o`, executables, etc.) that will cause severe merge conflicts if tracked. 

This guide outlines our mandatory Git workflow, branch protections, and daily development loop using **GitHub CLI** for web authentication. **Read this entire document before writing any code.**

---

### Part 1. Install and Authenticate via Web Browser (GitHub CLI)

Instead of dealing with SSH keys or Personal Access Tokens, we use the official GitHub CLI to log in and use the GitHub CLI to authenticate via your web browser.

#### Step A: Install GitHub CLI (`gh`)

In your Ubuntu/WSL2 terminal, run:

```bash
sudo apt update
sudo apt install gh -y

```

#### Step B: Run the Web Login Command

Start the interactive web login process:

```bash
gh auth login

```

#### Step C: Answer the Prompts

Select the following options when prompted:

1. **What account do you want to log into?** -> Select `GitHub.com`
2. **What is your preferred protocol for Git operations?** -> Select `HTTPS`
3. **Authenticate Git with your GitHub credentials?** -> Type `Y` and press Enter *(This makes Git automatically use this login for `git push`/`pull`!)*
4. **How would you like to authenticate GitHub CLI?** -> Select `Login with a web browser`

#### Step D: Complete Browser Activation

1. The terminal will output a **one-time 8-character code** (e.g., `XXXX-XXXX`). Copy this code.
2. Press **Enter**. It will attempt to open your default Windows/Linux browser.
*(If it does not open automatically, manually go to: **https://github.com/login/device**)* or the URL that will be provided
3. Paste your 8-character code into the browser, click **Continue**, and authorize the login.
4. Go back to your terminal. It will say `✓ Authentication complete`. You are now logged in!

## Part 2: First-Time Setup (Do Once)

Before cloning, you must configure your Git identity

### 1. Configure Your Git Identity
Open your WSL2/Linux terminal and run these commands (replace with your actual name and GitHub email):
```bash
git config --global user.name "Your Real Name"
git config --global user.email "your-github-email@example.com"

```

### 2. Clone the Repository

With the CLI authenticated, you can clone the repository seamlessly using `gh`:

```bash
gh repo clone https://github.com/Khobbygriff/maze-game-asm
cd maze-game-asm

```

---

## Part 2: The Core Workflow (Every Time You Code)

Our `main` branch is protected. You **cannot** push code directly to `main`. You must follow these 5 steps for every single change you make.

```
[Remote main] ──(Pull)──> [Local main] ──(Branch)──> [Local Feature] ──(Push)──> [Pull Request] ──(Merge)──> [Remote main]

```

### Step 1: Update Your Local Code

Before starting any new work, make sure you have the absolute latest version of the team's code:

```bash
git checkout main
git pull origin main

```

### Step 2: Create a Feature Branch

Create an isolated branch for the specific task you are working on. Name it descriptively:

```bash
git checkout -b feature/implement-player-movement

```

*Never write code while on the `main` branch.*

### Step 3: Write, Assemble, and Test

Write your assembly code. Assemble and link it in WSL2 to test your work:

```bash
# Example compilation (NASM + LD)
nasm -f elf64 player.asm -o player.o
ld player.o -o play_game
./play_game

```

### Step 4: Stage and Commit ONLY Source Files

Do **NOT** commit compiled binaries (`.o`, `.out`, or executables). They do not belong in version control.

1. Run `git status` to verify what files changed:
```bash
git status

```


2. Stage only your source files (e.g., `.asm`, `.s`, `.h`):
```bash
git add player.asm

```


3. Save your snapshot with a clear, descriptive message:
```bash
git commit -m "Added keyboard input handling subroutine in player.asm"

```



### Step 5: Push Your Branch to GitHub

Send your branch to the remote repository on GitHub:

```bash
git push origin feature/implement-player-movement

```

*(Because of our GitHub CLI setup, this push will authorize automatically without prompting you for password/token details!)*

---

## Part 3: Merging Your Code (Pull Requests)

Once your branch is pushed, you must merge it into the main codebase via GitHub.

1. Open our repository page on [GitHub](https://github.com/Khobbygriff/maze-game-asm).
2. Look for the yellow banner that says **"Compare & pull request"** and click it.
3. Write a brief description of what your assembly code does and any dependencies.
4. Click **Create pull request**.
5. **Request a Review:** At least one other classmate must look over your code, approve the changes, and approve the PR.
6. Once approved, click the green **Merge pull request** button to combine your branch with `main`.

---

## Part 4: Common Git Emergencies & Fixes

### Scenario A: "I accidentally started writing code directly on the `main` branch!"

**Do NOT commit yet.** Run this immediately to move your changes to a safe branch:

```bash
git checkout -b feature/my-new-branch

```

Git will safely carry your uncommitted changes over to the new branch, leaving `main` clean.

### Scenario B: "Git is showing merge conflicts!"

This happens when two people edit the same lines of the same file.

1. Open the conflicting file in your editor (VS Code, Nano, Vim).
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
4. Save the file, run `git add <file>`, and then `git commit` to resolve the conflict.

```

***

For a visual step-by-step setup walkthrough of this specific terminal installation process, you can watch this video on [How to install Git and run gh auth login](https://www.youtube.com/watch?v=gK5NrnWg150) to see how the interactive prompts look in real-time.


http://googleusercontent.com/youtube_content/5

