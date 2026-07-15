;=========================================================
; player.asm
;
; Player management.
;
; Functions:
;
;   spawn_player(row, col)  -- place player at level start
;   draw_player()
;   erase_player()
;   move_player(key)        -- attempt to move, with collision
;
;=========================================================


section .data

player_row db 3
player_col db 8

player_symbol db '@'

; Temporary movement storage
new_row db 0
new_col db 0


section .text


global draw_player
global erase_player
global move_player
global spawn_player

global player_row
global player_col

extern move_cursor
extern print_char
extern get_tile
extern set_color
extern reset_color

; Mirror of terminal.asm's COLOR_PLAYER -- must stay in sync.
COLOR_PLAYER equ 1


;=========================================================
;
; spawn_player(row, col)
;
; Places the player at the given starting coordinates.
; Called whenever a level is (re)loaded, since each level
; has its own start position.
;
; Input:
;
;   DIL = row
;   SIL = col
;
;=========================================================

spawn_player:

    mov [rel player_row],dil
    mov [rel player_col],sil

    ret


;=========================================================
;
; draw_player()
;
;=========================================================


draw_player:

    ; player_row/player_col are 0-indexed maze array
    ; coordinates (row 0 = the maze's top wall row), but
    ; move_cursor/ANSI cursor positioning is 1-indexed (row 1
    ; = the terminal's actual top line). Every other caller of
    ; move_cursor in this codebase already accounts for this
    ; (e.g. the HUD uses current_height+1, not current_height),
    ; so the +1 belongs here too -- without it the player glyph
    ; (and erase_player's blank-out) lands one row/col above and
    ; left of where the maze tile actually is, which is what
    ; caused wall characters at row/col 0 to get permanently
    ; blanked the first time the player moved away from them.

    movzx rdi,byte [rel player_row]
    inc rdi
    movzx rsi,byte [rel player_col]
    inc rsi

    call move_cursor

    mov al,COLOR_PLAYER
    call set_color

    mov al,[rel player_symbol]
    call print_char

    call reset_color

    ret


;=========================================================
;
; erase_player()
;
;=========================================================


erase_player:

    ; Same 0-indexed -> 1-indexed ANSI conversion as
    ; draw_player -- see the comment there for why. Without
    ; this, erase_player was blanking the cell one row/col
    ; above-left of the player's actual maze position, which
    ; for a player standing near row/col 0 meant permanently
    ; erasing a wall character instead of the player's own
    ; (correctly blank) previous tile.

    movzx rdi,byte [rel player_row]
    inc rdi
    movzx rsi,byte [rel player_col]
    inc rsi

    call move_cursor

    mov al,' '
    call print_char

    ret


;=========================================================
;
; move_player()
;
; Input:
;
;   AL = key ('w'/'a'/'s'/'d')
;
; Moves the player one tile in the requested direction if
; the destination tile is not a wall. Does nothing (silently)
; on an unrecognized key -- callers are expected to have
; already filtered control keys like ESC before calling this.
;
;=========================================================


move_player:

    ; default: new position = current position

    mov ah,al                  ; stash the key in AH, we need AL free

    mov al,[rel player_row]
    mov [rel new_row],al

    mov al,[rel player_col]
    mov [rel new_col],al

    mov al,ah                  ; restore key into AL for comparisons

    cmp al,'w'
    je .move_up

    cmp al,'s'
    je .move_down

    cmp al,'a'
    je .move_left

    cmp al,'d'
    je .move_right

    ret


.move_up:
    dec byte [rel new_row]
    jmp .check_move

.move_down:
    inc byte [rel new_row]
    jmp .check_move

.move_left:
    dec byte [rel new_col]
    jmp .check_move

.move_right:
    inc byte [rel new_col]
    jmp .check_move


;=========================================================
; Check if new position is valid, and commit it if so.
;=========================================================


.check_move:

    movzx rdi,byte [rel new_row]
    movzx rsi,byte [rel new_col]

    call get_tile

    cmp al,'#'
    je .blocked

    mov al,[rel new_row]
    mov [rel player_row],al

    mov al,[rel new_col]
    mov [rel player_col],al

.blocked:

    ret
