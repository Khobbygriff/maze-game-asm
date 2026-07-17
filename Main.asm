;=========================================================
; main.asm
;
; Orchestrates the overall game flow:
;
;   1. Enable raw keyboard mode (real-time input)
;   2. For each level:
;        - load level data, spawn player
;        - draw maze + HUD
;        - loop: read key -> move -> check win -> redraw
;        - on win, show "level complete" and advance
;   3. On completing all levels, show final score screen
;   4. Always restore the terminal before exiting
;
;=========================================================


section .data

level_label       db "LEVEL "
level_label_len   equ $ - level_label

moves_label       db "  MOVES: "
moves_label_len   equ $ - moves_label

score_label       db "  SCORE: "
score_label_len   equ $ - score_label

quit_hint         db "  (WASD to move, R to restart, ESC to quit, H for help)"
quit_hint_len     equ $ - quit_hint

final_score_label db "FINAL SCORE: "
final_score_label_len equ $ - final_score_label

name_prompt      db "Enter your name: "
name_prompt_len  equ $ - name_prompt

name_greeting_prefix     db "  Player: "
name_greeting_prefix_len equ $ - name_greeting_prefix

highscore_header    db "HIGH SCORES:"
highscore_header_len equ $ - highscore_header

score_separator     db " - "
score_separator_len equ $ - score_separator

; --- Splash screen ---
; Cleared and redrawn as a set of print_string calls at
; fixed rows rather than one giant multi-line literal, since
; NASM db strings can't easily embed row-positioning escape
; codes per line.

splash_title      db "======  ASM MAZE ESCAPE  ======"
splash_title_len  equ $ - splash_title

splash_hint       db "Press any key to start  --  press H for help"
splash_hint_len   equ $ - splash_hint

level_select_prompt db "Select starting level: [1] [2] [3]   (press H for help)"
level_select_prompt_len equ $ - level_select_prompt

; --- Help screen ---

help_title        db "======  HELP  ======"
help_title_len    equ $ - help_title

help_line1        db "WASD ....... move"
help_line1_len    equ $ - help_line1

help_line2        db "ESC ........ quit"
help_line2_len    equ $ - help_line2

help_line3        db "Yellow O ... coin  (+10 points)"
help_line3_len    equ $ - help_line3

help_line4        db "Cyan   * ... gem   (+25 points)"
help_line4_len    equ $ - help_line4

help_line5        db "Green  E ... exit  (finishes the level)"
help_line5_len    equ $ - help_line5

help_line6        db "Red    X ... hazard (-50 points, resets position)"
help_line6_len    equ $ - help_line6

help_back_hint    db "Press any key to return"
help_back_hint_len equ $ - help_back_hint

; Points awarded for finishing a level, scaled down by the
; number of moves taken -- fewer moves, higher bonus. Encourages
; efficient pathing rather than just wandering to the exit.
LEVEL_BASE_SCORE equ 1000

PLAYER_NAME_MAX_LEN equ 24


section .bss

hud_number_buffer resb 32
player_name        resb PLAYER_NAME_MAX_LEN


section .text


global _start


extern clear_screen
extern draw_maze
extern draw_player
extern erase_player
extern read_key
extern move_player
extern check_win
extern check_collect
extern get_game_state
extern reset_game_state
extern current_level_index
extern advance_level
extern record_move
extern get_move_count
extern get_score
extern add_score
extern win_message
extern win_message_len
extern all_done_message
extern all_done_message_len
extern load_level
extern spawn_player
extern enable_raw_mode
extern disable_raw_mode
extern move_cursor
extern print_string
extern print_char
extern int_to_string
extern current_height
extern read_line
extern set_color
extern reset_color
extern load_highscores
extern save_highscores
extern insert_highscore
extern highscore_table
extern restart_level
extern mark_visited
extern player_row
extern player_col
extern check_hazard
extern set_level_index
extern reset_score

; Mirror of terminal.asm's color constants -- must stay in
; sync (NASM equ constants don't cross files).
COLOR_HUD   equ 5
COLOR_TITLE equ 6


_start:

    ;------------------------------------------
    ; Ask for the player's name FIRST, while the
    ; terminal is still in normal (canonical) mode.
    ; read_line relies on the terminal's own line
    ; editing/echo, which raw mode disables -- so
    ; this must happen before enable_raw_mode.
    ;------------------------------------------

    mov rsi,name_prompt
    mov rdx,name_prompt_len
    call print_string

    lea rdi,[rel player_name]
    mov rsi,PLAYER_NAME_MAX_LEN
    call read_line

    call load_highscores

    call enable_raw_mode


splash_screen:

    call clear_screen

    mov rdi,8
    mov rsi,10
    call move_cursor

    mov al,COLOR_TITLE
    call set_color

    mov rsi,splash_title
    mov rdx,splash_title_len
    call print_string

    call reset_color

    mov rdi,10
    mov rsi,10
    call move_cursor

    mov rsi,name_greeting_prefix
    mov rdx,name_greeting_prefix_len
    call print_string

    call print_player_name

    ; Display high scores

    call display_highscores

    mov rdi,13
    mov rsi,5
    call move_cursor

    mov rsi,level_select_prompt
    mov rdx,level_select_prompt_len
    call print_string

.level_select_loop:

    call read_key

    cmp al,27                  ; ESC to quit
    je quit

    cmp al,'h'
    je help_screen
    cmp al,'H'
    je help_screen

    cmp al,'1'
    je .level_1
    cmp al,'2'
    je .level_2
    cmp al,'3'
    je .level_3

    ; Any other key - ignore and keep waiting
    jmp .level_select_loop

.level_1:

    xor dil,dil                ; level index 0
    call set_level_index
    jmp start_level

.level_2:

    mov dil,1                  ; level index 1
    call set_level_index
    jmp start_level_with_reset

.level_3:

    mov dil,2                  ; level index 2
    call set_level_index
    jmp start_level_with_reset

start_level_with_reset:

    ; Reset score to 0 for non-level-1 starts
    call reset_score
    jmp start_level


help_screen:

    call clear_screen

    mov rdi,3
    mov rsi,12
    call move_cursor

    mov al,COLOR_TITLE
    call set_color

    mov rsi,help_title
    mov rdx,help_title_len
    call print_string

    call reset_color

    mov rdi,5
    mov rsi,5
    call move_cursor
    mov rsi,help_line1
    mov rdx,help_line1_len
    call print_string

    mov rdi,6
    mov rsi,5
    call move_cursor
    mov rsi,help_line2
    mov rdx,help_line2_len
    call print_string

    mov rdi,7
    mov rsi,5
    call move_cursor
    mov rsi,help_line3
    mov rdx,help_line3_len
    call print_string

    mov rdi,8
    mov rsi,5
    call move_cursor
    mov rsi,help_line4
    mov rdx,help_line4_len
    call print_string

    mov rdi,9
    mov rsi,5
    call move_cursor
    mov rsi,help_line5
    mov rdx,help_line5_len
    call print_string

    mov rdi,10
    mov rsi,5
    call move_cursor
    mov rsi,help_line6
    mov rdx,help_line6_len
    call print_string

    mov rdi,12
    mov rsi,5
    call move_cursor
    mov rsi,help_back_hint
    mov rdx,help_back_hint_len
    call print_string

    call read_key

    jmp splash_screen


;=========================================================
;
; print_player_name()
;
; Prints the null-terminated player_name buffer using
; print_len_string's measuring approach. Small standalone
; helper since player_name isn't produced by int_to_string
; (so callers elsewhere shouldn't assume that).
;
;=========================================================

print_player_name:

    lea rsi,[rel player_name]
    call print_len_string

    ret


;=========================================================
;
; display_highscores()
;
; Displays the top 3 high scores on the splash screen.
;
;=========================================================

display_highscores:

    push rbx
    push r12
    push r13

    mov rdi,14
    mov rsi,5
    call move_cursor

    mov al,COLOR_HUD
    call set_color

    mov rsi,highscore_header
    mov rdx,highscore_header_len
    call print_string

    call reset_color

    ; Loop through 3 records

    xor rbx,rbx                ; rbx = record index

.hs_loop:

    cmp rbx,3
    jge .hs_done

    ; Calculate record address

    lea r12,[rel highscore_table]
    mov rax,rbx
    imul rax,28                ; HIGHSCORE_RECORD_SIZE
    add r12,rax

    ; Check if score is non-zero

    mov r13,[r12+20]           ; score field (offset 20)
    cmp r13,0
    je .hs_next                ; skip empty records

    ; Position cursor for this entry

    mov rdi,15
    mov rsi,5
    add rdi,rbx
    call move_cursor

    ; Print rank

    mov al,'1'
    add al,bl
    call print_char

    mov al,'.'
    call print_char

    mov al,' '
    call print_char

    ; Print name (up to 20 chars, stop at null)

    mov rdi,r12
    mov rcx,20

.name_loop:
    cmp rcx,0
    je .name_done
    mov al,[rdi]
    cmp al,0
    je .name_done
    call print_char
    inc rdi
    dec rcx
    jmp .name_loop

.name_done:

    ; Print separator

    mov rsi,score_separator
    mov rdx,score_separator_len
    call print_string

    ; Print score

    mov rax,r13
    lea rdi,[rel hud_number_buffer]
    call int_to_string

    lea rsi,[rel hud_number_buffer]
    call print_len_string

.hs_next:

    inc rbx
    jmp .hs_loop

.hs_done:

    pop r13
    pop r12
    pop rbx
    ret


start_level:

    ;------------------------------------------
    ; Load current level's maze + start position
    ;
    ; AL = start row, AH = start col (from load_level)
    ;------------------------------------------

    movzx rdi,byte [rel current_level_holder]
    call current_level_index
    movzx rdi,al

    call load_level

    ; AL/AH hold start row/col from load_level. AH cannot be
    ; mixed with a REX-prefixed register (like SIL) in the
    ; same instruction, so stage the column through CL first.

    mov cl,ah          ; cl = start col
    mov dil,al         ; dil = start row
    mov sil,cl         ; sil = start col
    call spawn_player

    call reset_game_state


redraw_level:

    call clear_screen
    call draw_maze
    call draw_player
    call draw_hud


game_loop:

    ;------------------------------------------
    ; Read keyboard input (blocks until a key
    ; is pressed -- raw mode means no Enter
    ; needed and no line echo)
    ;------------------------------------------

    call read_key

    ; ESC exits immediately

    cmp al,27
    je quit

    ; R key restarts the current level

    cmp al,'r'
    je .restart_key
    cmp al,'R'
    je .restart_key

    ; Ignore keys that aren't movement keys so the move
    ; counter and redraw only fire on real attempts

    cmp al,'w'
    je .valid_key
    cmp al,'a'
    je .valid_key
    cmp al,'s'
    je .valid_key
    cmp al,'d'
    je .valid_key

    jmp game_loop

.restart_key:

    call restart_level
    jmp redraw_level

.valid_key:

    ; AL holds the pressed key here, but erase_player() will
    ; clobber AL (it uses it to print a space). Preserve the
    ; key in a callee-saved register across that call so
    ; move_player() still sees the correct direction.

    mov bl,al

    ; Save old player position for breadcrumb marking

    movzx rdi,byte [rel player_row]
    movzx rsi,byte [rel player_col]

    call record_move

    call erase_player

    mov al,bl
    call move_player

    ; Mark the old position as visited (breadcrumb)
    ; Only mark if the move was successful (position changed)

    movzx rax,byte [rel player_row]
    cmp dil,al
    jne .mark_old_pos
    movzx rax,byte [rel player_col]
    cmp sil,al
    je .skip_breadcrumb

.mark_old_pos:

    mov rdi,rdi                ; old row
    mov rsi,rsi                ; old col
    call mark_visited

.skip_breadcrumb:

    call check_collect

    call check_hazard

    cmp al,1
    je .hazard_triggered

    call check_win

    call get_game_state

    cmp al,1
    je level_won

    call draw_player

    call update_hud

    jmp game_loop

.hazard_triggered:

    ; Player was reset to start - redraw immediately
    jmp redraw_level


level_won:

    ;------------------------------------------
    ; Award score: base bonus minus a penalty
    ; per move taken, floored at a small
    ; minimum so it's never negative/zero.
    ;------------------------------------------

    call get_move_count        ; rax = moves taken

    mov rbx,rax
    mov rax,LEVEL_BASE_SCORE

    ; bonus = max(100, BASE - moves*5)

    mov rcx,rbx
    imul rcx,5
    sub rax,rcx

    cmp rax,100
    jge .bonus_ok
    mov rax,100

.bonus_ok:

    mov rdi,rax
    call add_score

    call clear_screen

    mov rdi,10
    mov rsi,20
    call move_cursor

    mov rsi,win_message
    mov rdx,win_message_len
    call print_string

    ; Wait for ENTER to continue, but allow ESC to quit

.wait_for_enter:
    call read_key

    cmp al,27                  ; ESC to quit
    je quit

    cmp al,13                  ; Carriage return (Enter)
    je .enter_pressed
    cmp al,10                  ; Newline (Enter on some terminals)
    je .enter_pressed

    ; Any other key - ignore and keep waiting
    jmp .wait_for_enter

.enter_pressed:
    call advance_level         ; AL = 1 if more levels remain

    cmp al,1
    je start_level

    jmp all_levels_done


all_levels_done:

    call clear_screen

    mov rdi,10
    mov rsi,15
    call move_cursor

    mov rsi,all_done_message
    mov rdx,all_done_message_len
    call print_string

    ; Wait for ENTER to see final score, but allow ESC to quit

.wait_for_final_enter:
    call read_key

    cmp al,27                  ; ESC to quit
    je quit

    cmp al,13                  ; Carriage return (Enter)
    je .show_final_score
    cmp al,10                  ; Newline (Enter on some terminals)
    je .show_final_score

    ; Any other key - ignore and keep waiting
    jmp .wait_for_final_enter

.show_final_score:

    call clear_screen

    mov rdi,10
    mov rsi,15
    call move_cursor

    mov rsi,all_done_message
    mov rdx,all_done_message_len
    call print_string

    ; --- print final score on the next line ---

    mov rdi,12
    mov rsi,15
    call move_cursor

    mov rsi,final_score_label
    mov rdx,final_score_label_len
    call print_string

    call get_score
    lea rdi,[rel hud_number_buffer]
    call int_to_string

    ; print the number string (find its length first)

    lea rsi,[rel hud_number_buffer]
    xor rdx,rdx

.len_loop:
    cmp byte [rsi+rdx],0
    je .len_done
    inc rdx
    jmp .len_loop

.len_done:

    lea rsi,[rel hud_number_buffer]
    call print_string

    ; Insert high score and save

    call get_score
    mov rsi,rax
    lea rdi,[rel player_name]
    call insert_highscore

    call save_highscores

    call read_key

    jmp quit


;=========================================================
;
; draw_hud()
;
; Draws the status line below the maze: current level
; number, moves taken, and score. Called once per level
; load (full draw) -- update_hud() is used for cheaper
; per-move refreshes.
;
;=========================================================

draw_hud:

    ; Position the HUD one row below the current maze instead
    ; of a fixed row -- keeps it snug against small mazes and
    ; still clear of large ones, rather than leaving a fixed
    ; gap sized for the tallest level regardless of which one
    ; is actually loaded.

    mov al,COLOR_HUD
    call set_color

    mov rdi,[rel current_height]
    inc rdi
    mov rsi,0
    call move_cursor

    mov rsi,level_label
    mov rdx,level_label_len
    call print_string

    call current_level_index
    inc al                      ; display as 1-based
    movzx rax,al
    lea rdi,[rel hud_number_buffer]
    call int_to_string

    lea rsi,[rel hud_number_buffer]
    call print_len_string

    mov rsi,quit_hint
    mov rdx,quit_hint_len
    call print_string

    ; player name goes on its own row so it's not squeezed
    ; onto an already-long level/hint line

    mov rdi,[rel current_height]
    add rdi,3
    mov rsi,0
    call move_cursor

    mov rsi,name_greeting_prefix
    mov rdx,name_greeting_prefix_len
    call print_string

    call print_player_name

    call reset_color

    call update_hud

    ret


;=========================================================
;
; update_hud()
;
; Redraws just the moves/score portion of the HUD (row 21).
; Kept separate from draw_hud so we're not reprinting the
; static level/hint text on every single keypress.
;
;=========================================================

update_hud:

    ; Same dynamic positioning as draw_hud, one row further
    ; down (current_height + 2) so it sits directly under the
    ; "LEVEL n ..." line rather than overlapping it.

    mov al,COLOR_HUD
    call set_color

    mov rdi,[rel current_height]
    add rdi,2
    mov rsi,0
    call move_cursor

    mov rsi,moves_label
    mov rdx,moves_label_len
    call print_string

    call get_move_count
    lea rdi,[rel hud_number_buffer]
    call int_to_string

    lea rsi,[rel hud_number_buffer]
    call print_len_string

    mov rsi,score_label
    mov rdx,score_label_len
    call print_string

    call get_score
    lea rdi,[rel hud_number_buffer]
    call int_to_string

    lea rsi,[rel hud_number_buffer]
    call print_len_string

    ; clear any leftover characters from a longer previous
    ; number by padding with spaces

    mov rsi,hud_clear_pad
    mov rdx,hud_clear_pad_len
    call print_string

    call reset_color

    ret


;=========================================================
;
; print_len_string(rsi = null-terminated string)
;
; Small helper: measures a null-terminated string (as
; produced by int_to_string) and prints it via print_string,
; which needs an explicit length rather than a terminator.
;
;=========================================================

print_len_string:

    push rsi

    xor rdx,rdx

.measure:
    cmp byte [rsi+rdx],0
    je .measured
    inc rdx
    jmp .measure

.measured:

    pop rsi
    call print_string

    ret


quit:

    call disable_raw_mode

    mov rax,60
    mov rdi,0
    syscall


section .data

; index of the "current level" isn't actually stored here --
; game.asm is the source of truth via current_level_index().
; This byte exists only so the very first call before any
; level has loaded has a harmless placeholder to read;
; it is not used for anything else.
current_level_holder db 0

hud_clear_pad     db "        "
hud_clear_pad_len equ $ - hud_clear_pad
