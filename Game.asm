;=========================================================
; game.asm
;
; Owns overall game/session state:
;
;   - Win/lose/running status for the current level
;   - Which level we're on
;   - Score and move counter
;   - Collectibles (coins/gems) per level
;
; Functions:
;
;   check_win()
;   get_game_state()
;   reset_game_state()
;   current_level_index()
;   advance_level()
;   record_move()
;   get_move_count()
;   get_score()
;   add_score(points)
;   check_collect()
;   get_collectible_tile(row,col)
;   is_collectible_taken(index)
;
;=========================================================


section .data


;---------------------------------------------------------
; Game states
;
; 0 = running
; 1 = won current level
; 2 = all levels complete
;---------------------------------------------------------

game_state db 0

; 0-based index of the level currently being played
level_index db 0


;---------------------------------------------------------
; High-score file format
;
; File: highscores.dat
; Fixed binary format: 3 records, each record is:
;   - Player name: 20 bytes (null-padded if shorter)
;   - Score: 8 bytes (qword, little-endian)
; Total file size: 3 * 28 = 84 bytes
;---------------------------------------------------------

HIGHSCORE_NAME_MAX  equ 20
HIGHSCORE_SCORE_SIZE equ 8
HIGHSCORE_RECORD_SIZE equ (HIGHSCORE_NAME_MAX + HIGHSCORE_SCORE_SIZE)
HIGHSCORE_NUM_RECORDS equ 3
HIGHSCORE_FILE_SIZE equ (HIGHSCORE_NUM_RECORDS * HIGHSCORE_RECORD_SIZE)

highscore_filename db "highscores.dat", 0

win_message      db "LEVEL COMPLETE! Press ENTER to continue"
win_message_len  equ $ - win_message

all_done_message     db "YOU ESCAPED EVERY MAZE!"
all_done_message_len equ $ - all_done_message


;---------------------------------------------------------
; Collectibles
;
; Coordinates below were chosen with a BFS solver run
; against each level's actual maze data, so every item sits
; on a tile that's provably reachable on the way from P to
; E (not just "looks open" by eye) -- same discipline used
; to verify the mazes themselves are solvable.
;
; Fixed at 4 items per level: 2 coins, 2 gems. Layout is
; (row, col, type) as 3 bytes per entry; a level with fewer
; than the max uses row=255 as an unused/"no item" marker
; (255 is never a valid row for these maze sizes, so it's a
; safe sentinel rather than colliding with real data).
;
; type: 0 = coin (10 pts), 1 = gem (25 pts)
;---------------------------------------------------------

COLLECTIBLE_TYPE_COIN equ 0
COLLECTIBLE_TYPE_GEM  equ 1
COLLECTIBLES_PER_LEVEL equ 4
COLLECTIBLE_ENTRY_SIZE equ 3

COIN_SCORE equ 10
GEM_SCORE  equ 25
HAZARD_PENALTY equ 50

level1_collectibles:
    db 3,4,COLLECTIBLE_TYPE_COIN
    db 2,11,COLLECTIBLE_TYPE_GEM
    db 6,19,COLLECTIBLE_TYPE_COIN
    db 6,9,COLLECTIBLE_TYPE_GEM

level2_collectibles:
    db 6,25,COLLECTIBLE_TYPE_COIN
    db 11,21,COLLECTIBLE_TYPE_GEM
    db 5,19,COLLECTIBLE_TYPE_COIN
    db 2,7,COLLECTIBLE_TYPE_GEM

level3_collectibles:
    db 4,35,COLLECTIBLE_TYPE_COIN
    db 12,35,COLLECTIBLE_TYPE_GEM
    db 3,20,COLLECTIBLE_TYPE_COIN
    db 15,20,COLLECTIBLE_TYPE_GEM

;----------------------------------------------------------
; Level 4 collectibles -- deliberately split two ways:
;
;   - 2 "legit" items sit ON the true solution path (roughly
;     a third and two-thirds of the way along it), same as
;     every other level -- a normal progress reward.
;   - 2 "bait" items sit deep inside two of the level's
;     decoy loops (see the comment above level4_data in
;     maze.asm), 22-23 tiles down a dead end. Finding a coin
;     or gem down a side corridor is meant to read as "you're
;     on the right track," which is exactly the wrong
;     conclusion in a maze whose whole point is that some
;     inviting-looking branches don't lead anywhere.
;
; All 4 positions were checked against the same rule used for
; every other level: each sits on a tile reachable from P AND
; has at least two open neighboring tiles, so nothing renders
; visually embedded in a wall.
;----------------------------------------------------------

level4_collectibles:
    db 4,17,COLLECTIBLE_TYPE_COIN    ; legit -- on true path
    db 11,33,COLLECTIBLE_TYPE_GEM    ; legit -- on true path
    db 1,16,COLLECTIBLE_TYPE_COIN    ; bait  -- dead-end loop, depth 22
    db 3,30,COLLECTIBLE_TYPE_GEM     ; bait  -- dead-end loop, depth 23

collectible_table:
    dq level1_collectibles
    dq level2_collectibles
    dq level3_collectibles
    dq level4_collectibles


section .bss

; "collected" flags for the current level's 4 items, reset
; on every level load. Separate from the (row,col,type) data
; above since that data is level-static and this is runtime
; per-level state.
collected_flags resb COLLECTIBLES_PER_LEVEL


;---------------------------------------------------------
; In-memory high-score table (3 records)
;---------------------------------------------------------

highscore_table resb HIGHSCORE_FILE_SIZE


; Breadcrumb trail: visited tiles for current level
; Maximum maze size is level 3: 39x17 = 663 tiles
; We use a byte per tile (0 = not visited, 1 = visited)
breadcrumb_map resb 663


; Moves taken on the current level
move_count resq 1

; Cumulative score across all levels
score resq 1

; Pointer to the current level's collectible table, set by
; reset_game_state (which is called once per level load).
current_collectible_table resq 1


section .text


global check_win
global get_game_state
global reset_game_state
global current_level_index
global advance_level
global record_move
global get_move_count
global get_score
global add_score
global check_collect
global get_collectible_tile
global win_message
global win_message_len
global all_done_message
global all_done_message_len
global load_highscores
global save_highscores
global insert_highscore
global highscore_table
global restart_level
global mark_visited
global is_visited
global reset_breadcrumbs
global breadcrumb_map
global check_hazard
global set_level_index
global reset_score

extern get_tile
extern player_row
extern player_col
extern spawn_player
extern load_level
extern current_width

; NUM_LEVELS is defined in maze.asm; redeclare here as extern
; constant via a small wrapper isn't possible for `equ`
; across files in NASM, so game.asm asks maze.asm for the
; count through a tiny accessor instead of duplicating the
; literal.
extern get_num_levels


;=========================================================
;
; check_win()
;
; Checks whether the player is standing on the exit tile
; ('E'). If so, marks the level as won.
;
; Output:
;
;   game_state becomes 1 if the level was just won
;
;=========================================================


check_win:

    movzx rdi,byte [rel player_row]
    movzx rsi,byte [rel player_col]

    call get_tile

    cmp al,'E'
    jne .not_won

    mov byte [rel game_state],1

.not_won:

    ret


;=========================================================
;
; get_game_state()
;
; Output:
;
;   AL = current state (0=running, 1=level won, 2=all done)
;
;=========================================================


get_game_state:

    mov al,[rel game_state]
    ret


;=========================================================
;
; reset_game_state()
;
; Resets state to "running" and zeroes the move counter.
; Called at the start of every level (fresh maze = fresh
; move count, but score carries over between levels).
;
;=========================================================


reset_game_state:

    mov byte [rel game_state],0
    mov qword [rel move_count],0

    ; clear all "collected" flags for the fresh level

    xor rax,rax
    mov rcx,COLLECTIBLES_PER_LEVEL
    lea rdi,[rel collected_flags]

.clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .clear_loop

    ; Reset breadcrumbs for the fresh level

    call reset_breadcrumbs

    ; point current_collectible_table at this level's table.
    ; level_index is already tracked in this file (used by
    ; current_level_index/advance_level), so we read it
    ; directly rather than requiring a parameter.

    movzx rax,byte [rel level_index]
    mov rcx,8
    mul rcx                    ; rax = level_index * 8 (qword stride)

    lea rbx,[rel collectible_table]
    add rbx,rax

    mov rcx,[rbx]
    mov [rel current_collectible_table],rcx

    ret


;=========================================================
;
; current_level_index()
;
; Output:
;
;   AL = 0-based index of the level being played
;
;=========================================================


current_level_index:

    mov al,[rel level_index]
    ret


;=========================================================
;
; advance_level()
;
; Moves to the next level if one exists.
;
; Output:
;
;   AL = 1 if a next level exists and was loaded,
;        0 if that was the last level (game_state -> 2)
;
; IMPORTANT: level_index is deliberately NOT incremented
; past NUM_LEVELS-1. reset_game_state() uses level_index to
; index directly into collectible_table with no bounds check
; of its own -- if level_index were allowed to sit at
; NUM_LEVELS (one past the last valid entry) and
; reset_game_state() were ever called again afterward (e.g.
; a future "play again" path), it would read one descriptor
; past the end of collectible_table. Today nothing calls
; reset_game_state() after the last level, so this couldn't
; yet happen -- clamping here means it never can, regardless
; of what main.asm does with game_state later.
;
;=========================================================


advance_level:

    call get_num_levels        ; AL = NUM_LEVELS
    dec al                     ; AL = highest valid index

    cmp [rel level_index],al
    jge .no_more_levels

    inc byte [rel level_index]
    mov al,1
    ret

.no_more_levels:

    ; stay on the last valid index -- do not increment past it

    mov byte [rel game_state],2
    mov al,0
    ret


;=========================================================
;
; record_move()
;
; Increments the move counter for the current level.
; Call this once per accepted keypress (movement attempt),
; whether or not the move was actually valid -- this keeps
; the counter simple to reason about: it's an input counter,
; not a "successful steps" counter.
;
;=========================================================


record_move:

    inc qword [rel move_count]
    ret


;=========================================================
;
; get_move_count()
;
; Output:
;
;   RAX = moves taken on the current level
;
;=========================================================


get_move_count:

    mov rax,[rel move_count]
    ret


;=========================================================
;
; get_score()
;
; Output:
;
;   RAX = cumulative score
;
;=========================================================


get_score:

    mov rax,[rel score]
    ret


;=========================================================
;
; add_score(points)
;
; Input:
;
;   RDI = points to add (can be a computed bonus)
;
;=========================================================


add_score:

    add [rel score],rdi
    ret


;=========================================================
;
; check_collect()
;
; Checks whether the player's current position matches an
; uncollected item in the current level's collectible
; table. If so, marks it collected and awards its score.
; Called once per accepted move, right after move_player --
; same call pattern as check_win().
;
; Silently does nothing if the player isn't standing on an
; item, or the item there was already collected.
;
;=========================================================


check_collect:

    push rbx
    push r12
    push r13
    push r14

    movzx r12,byte [rel player_row]
    movzx r13,byte [rel player_col]

    mov r14,[rel current_collectible_table]

    xor rcx,rcx                ; rcx = item index

.check_loop:

    cmp rcx,COLLECTIBLES_PER_LEVEL
    jge .done

    ; already collected? skip

    lea rbx,[rel collected_flags]
    cmp byte [rbx+rcx],0
    jne .next_item

    ; compute entry address: table + index*3

    mov rax,rcx
    imul rax,COLLECTIBLE_ENTRY_SIZE
    add rax,r14

    movzx rbx,byte [rax]        ; entry row
    cmp rbx,r12
    jne .next_item

    movzx rbx,byte [rax+1]      ; entry col
    cmp rbx,r13
    jne .next_item

    ; match -- mark collected and award score

    lea rbx,[rel collected_flags]
    mov byte [rbx+rcx],1

    movzx rbx,byte [rax+2]      ; type
    cmp rbx,COLLECTIBLE_TYPE_GEM
    je .award_gem

    mov rdi,COIN_SCORE
    jmp .award

.award_gem:

    mov rdi,GEM_SCORE

.award:

    call add_score
    jmp .done                   ; only one item can occupy a
                                 ; tile, so stop once matched

.next_item:

    inc rcx
    jmp .check_loop

.done:

    pop r14
    pop r13
    pop r12
    pop rbx

    ret


;=========================================================
;
; get_collectible_tile(row,col)
;
; Looks up whether an uncollected item sits at the given
; maze position, for draw_maze to render on top of the
; empty-space tile there.
;
; Input:
;
;   RDI = row
;   RSI = col
;
; Output:
;
;   AL = 0 if no item here (or it was already collected)
;   AL = 1 if a coin is here
;   AL = 2 if a gem is here
;
;=========================================================


get_collectible_tile:

    push rbx
    push r14

    mov r14,[rel current_collectible_table]

    xor rcx,rcx

.scan_loop:

    cmp rcx,COLLECTIBLES_PER_LEVEL
    jge .none

    lea rbx,[rel collected_flags]
    cmp byte [rbx+rcx],0
    jne .next

    mov rax,rcx
    imul rax,COLLECTIBLE_ENTRY_SIZE
    add rax,r14

    movzx rbx,byte [rax]
    cmp rbx,rdi
    jne .next

    movzx rbx,byte [rax+1]
    cmp rbx,rsi
    jne .next

    ; found an uncollected item at this position

    movzx rbx,byte [rax+2]
    cmp rbx,COLLECTIBLE_TYPE_GEM
    je .is_gem

    mov al,1                     ; coin
    jmp .found

.is_gem:

    mov al,2

.found:

    pop r14
    pop rbx
    ret

.next:

    inc rcx
    jmp .scan_loop

.none:

    xor al,al

    pop r14
    pop rbx
    ret


;=========================================================
;
; load_highscores()
;
; Loads high scores from highscores.dat file. If file doesn't
; exist or is corrupted, initializes empty table (all scores = 0).
;
;=========================================================

load_highscores:

    push rbx
    push r12
    push r13

    ; Try to open the file for reading

    mov rax,2                  ; open syscall
    mov rdi,highscore_filename
    mov rsi,0                  ; O_RDONLY
    mov rdx,0                  ; no mode needed for read-only
    syscall

    cmp rax,0
    jl .file_not_found         ; error opening file

    mov r12,rax                ; r12 = file descriptor

    ; Read the file

    mov rax,0                  ; read syscall
    mov rdi,r12                ; fd
    lea rsi,[rel highscore_table]
    mov rdx,HIGHSCORE_FILE_SIZE
    syscall

    mov r13,rax                ; r13 = bytes read

    ; Close the file

    mov rax,3                  ; close syscall
    mov rdi,r12
    syscall

    ; If we read less than expected, initialize to zeros

    cmp r13,HIGHSCORE_FILE_SIZE
    jge .done

.file_not_found:

    ; Initialize highscore_table to all zeros

    xor rax,rax
    mov rcx,HIGHSCORE_FILE_SIZE
    lea rdi,[rel highscore_table]

.init_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .init_loop

.done:

    pop r13
    pop r12
    pop rbx
    ret


;=========================================================
;
; save_highscores()
;
; Writes the current high-score table to highscores.dat.
; If write fails, silently continues (doesn't crash).
;
;=========================================================

save_highscores:

    push rbx
    push r12

    ; Open file for writing (create/truncate)

    mov rax,2                  ; open syscall
    mov rdi,highscore_filename
    mov rsi,0x241              ; O_WRONLY | O_CREAT | O_TRUNC
    mov rdx,0o644             ; rw-r--r--
    syscall

    cmp rax,0
    jl .done                   ; error opening file

    mov r12,rax                ; r12 = file descriptor

    ; Write the table

    mov rax,1                  ; write syscall
    mov rdi,r12
    lea rsi,[rel highscore_table]
    mov rdx,HIGHSCORE_FILE_SIZE
    syscall

    ; Close the file

    mov rax,3                  ; close syscall
    mov rdi,r12
    syscall

.done:

    pop r12
    pop rbx
    ret


;=========================================================
;
; insert_highscore(name_ptr, score)
;
; Inserts a new high score into the table if it qualifies.
; Maintains sorted order (highest first). Shifts out the
; lowest score if table is full.
;
; Input:
;   RDI = pointer to null-terminated player name
;   RSI = score (qword)
;
;=========================================================

insert_highscore:

    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12,rdi                ; r12 = name pointer
    mov r13,rsi                ; r13 = score to insert

    ; Find the lowest score in the table (last record)

    lea rbx,[rel highscore_table]
    add rbx,(HIGHSCORE_NUM_RECORDS - 1) * HIGHSCORE_RECORD_SIZE
    add rbx,HIGHSCORE_NAME_MAX ; skip to score field

    mov r14,[rbx]              ; r14 = lowest current score

    ; If table is full and new score is lower, don't insert

    cmp r14,0
    je .insert_needed          ; table has empty slots

    cmp r13,r14
    jle .done                  ; new score not high enough

.insert_needed:

    ; Find insertion position (first score lower than ours, or end)

    xor r15,r15                ; r15 = record index

.find_loop:

    cmp r15,HIGHSCORE_NUM_RECORDS
    je .insert_at_end

    lea rbx,[rel highscore_table]
    mov rax,r15
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax
    add rbx,HIGHSCORE_NAME_MAX ; skip to score field

    mov r14,[rbx]              ; current score at this position

    cmp r14,0
    je .insert_here            ; empty slot

    cmp r13,r14
    jg .insert_here            ; our score is higher

    inc r15
    jmp .find_loop

.insert_at_end:

    mov r15,HIGHSCORE_NUM_RECORDS - 1

.insert_here:

    ; Shift records down from insertion position

    cmp r15,HIGHSCORE_NUM_RECORDS - 1
    je .no_shift

.shift_loop:

    mov r14,r15
    inc r14
    cmp r14,HIGHSCORE_NUM_RECORDS
    jge .no_shift

    ; Calculate source and dest addresses

    lea rbx,[rel highscore_table]
    mov rax,r14
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax                ; source = record at r14

    lea rcx,[rel highscore_table]
    mov rdx,r15
    imul rdx,HIGHSCORE_RECORD_SIZE
    add rcx,rdx               ; dest = record at r15

    ; Copy one record (28 bytes)

    mov rdi,rcx
    mov rsi,rbx
    mov rcx,HIGHSCORE_RECORD_SIZE

.copy_loop:
    mov al,[rsi]
    mov [rdi],al
    inc rsi
    inc rdi
    dec rcx
    jnz .copy_loop

    inc r15
    jmp .shift_loop

.no_shift:

    ; Insert new record at position r15

    lea rbx,[rel highscore_table]
    mov rax,r15
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax                ; rbx = insertion point

    ; Copy name (up to HIGHSCORE_NAME_MAX, null-pad if shorter)

    mov rdi,rbx
    mov rsi,r12
    mov rcx,HIGHSCORE_NAME_MAX
    xor rdx,rdx                ; rdx = bytes copied

.name_loop:

    cmp rdx,HIGHSCORE_NAME_MAX
    jge .name_done

    mov al,[rsi]
    cmp al,0
    je .name_null_found

    mov [rdi],al
    inc rsi
    inc rdi
    inc rdx
    jmp .name_loop

.name_null_found:

    ; Pad remaining bytes with nulls

.pad_loop:

    cmp rdx,HIGHSCORE_NAME_MAX
    jge .name_done

    mov byte [rdi],0
    inc rdi
    inc rdx
    jmp .pad_loop

.name_done:

    ; Write score

    add rbx,HIGHSCORE_NAME_MAX
    mov [rbx],r13

.done:

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


;=========================================================
;
; restart_level()
;
; Restarts the current level: resets player position to start,
; resets move counter to 0, and resets collectibles to unclaimed.
; Does NOT reset cumulative score or change the level.
;
;=========================================================

restart_level:

    push rbx
    push r12

    ; Get current level index

    call current_level_index
    movzx rdi,al

    ; Reload level to get start position

    call load_level

    ; AL = start row, AH = start col from load_level

    mov cl,ah          ; cl = start col
    mov dil,al         ; dil = start row
    mov sil,cl         ; sil = start col
    call spawn_player

    ; Reset move counter

    mov qword [rel move_count],0

    ; Reset all "collected" flags for this level

    xor rax,rax
    mov rcx,COLLECTIBLES_PER_LEVEL
    lea rdi,[rel collected_flags]

.clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .clear_loop

    ; Reset breadcrumbs

    call reset_breadcrumbs

    pop r12
    pop rbx
    ret


;=========================================================
;
; reset_breadcrumbs()
;
; Clears the breadcrumb map for the current level.
; Called on level load and restart.
;
;=========================================================

reset_breadcrumbs:

    push rbx
    push rcx

    xor rax,rax
    mov rcx,663                ; max maze size
    lea rdi,[rel breadcrumb_map]

.bc_clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .bc_clear_loop

    pop rcx
    pop rbx
    ret


;=========================================================
;
; mark_visited(row, col)
;
; Marks a tile as visited in the breadcrumb map.
;
; Input:
;   RDI = row
;   RSI = col
;
;=========================================================

mark_visited:

    push rbx
    push rcx

    ; Calculate index: row * width + col

    mov rax,rdi
    mov rbx,[rel current_width]
    mul rbx
    add rax,rsi

    ; Mark as visited

    lea rbx,[rel breadcrumb_map]
    mov byte [rbx+rax],1

    pop rcx
    pop rbx
    ret


;=========================================================
;
; is_visited(row, col)
;
; Checks if a tile has been visited.
;
; Input:
;   RDI = row
;   RSI = col
;
; Output:
;   AL = 1 if visited, 0 if not
;
;=========================================================

is_visited:

    push rbx

    ; Calculate index: row * width + col

    mov rax,rdi
    mov rbx,[rel current_width]
    mul rbx
    add rax,rsi

    ; Check visited flag

    lea rbx,[rel breadcrumb_map]
    mov al,[rbx+rax]

    pop rbx
    ret


;=========================================================
;
; check_hazard()
;
; Checks if the player is standing on a hazard tile.
; If so, applies penalty and resets position to start.
;
; Output:
;   AL = 1 if hazard was triggered, 0 otherwise
;
;=========================================================

check_hazard:

    push rbx
    push r12
    push r13

    movzx rdi,byte [rel player_row]
    movzx rsi,byte [rel player_col]

    call get_tile

    cmp al,'X'
    jne .no_hazard

    ; Hazard triggered - deduct penalty from score

    mov rax,[rel score]
    cmp rax,HAZARD_PENALTY
    jge .deduct

    ; Score would go negative - clamp to 0

    mov qword [rel score],0
    jmp .reset_position

.deduct:

    sub rax,HAZARD_PENALTY
    mov [rel score],rax

.reset_position:

    ; Reset player to start position (like restart_level but
    ; without resetting move counter or collectibles)

    call current_level_index
    movzx rdi,al

    call load_level

    mov cl,ah
    mov dil,al
    mov sil,cl
    call spawn_player

    mov al,1
    jmp .done

.no_hazard:

    xor al,al

.done:

    pop r13
    pop r12
    pop rbx
    ret


;=========================================================
;
; set_level_index(level)
;
; Sets the current level index to the specified value.
; Used for level selection at splash screen.
;
; Input:
;   DIL = level index (0, 1, or 2 for levels 1, 2, 3)
;
;=========================================================

set_level_index:

    mov [rel level_index],dil
    ret


;=========================================================
;
; reset_score()
;
; Resets the cumulative score to 0.
; Used when starting from a non-level-1 start.
;
;=========================================================

reset_score:

    mov qword [rel score],0
    ret
