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

win_message      db "LEVEL COMPLETE!"
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

collectible_table:
    dq level1_collectibles
    dq level2_collectibles
    dq level3_collectibles


section .bss

; "collected" flags for the current level's 4 items, reset
; on every level load. Separate from the (row,col,type) data
; above since that data is level-static and this is runtime
; per-level state.
collected_flags resb COLLECTIBLES_PER_LEVEL


section .bss

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

extern get_tile
extern player_row
extern player_col

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
;=========================================================


advance_level:

    inc byte [rel level_index]

    call get_num_levels        ; AL = NUM_LEVELS

    cmp [rel level_index],al
    jl .more_levels

    ; no more levels -- whole game complete

    mov byte [rel game_state],2
    mov al,0
    ret

.more_levels:

    mov al,1
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
