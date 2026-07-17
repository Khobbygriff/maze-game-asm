;=========================================================
; terminal.asm
;
; Terminal control functions.
;
; Functions:
;   clear_screen()
;   print_char()
;   print_string(rsi=addr, rdx=len)
;   move_cursor(rdi=row, rsi=col)
;   enable_raw_mode()
;   disable_raw_mode()
;
; Uses Linux x86-64 syscalls directly (no libc).
;
;=========================================================


section .data


;---------------------------------------------------------
; ANSI escape sequence to clear screen
;
; ESC[2J  -> clear terminal
; ESC[H   -> move cursor to home position
;---------------------------------------------------------

clear_code db 27, "[2J", 27, "[H"
clear_len  equ $ - clear_code


;---------------------------------------------------------
; Hide / show terminal cursor (cosmetic, makes the game
; look less flickery while redrawing).
;---------------------------------------------------------

hide_cursor_code db 27, "[?25l"
hide_cursor_len  equ $ - hide_cursor_code

show_cursor_code db 27, "[?25h"
show_cursor_len  equ $ - show_cursor_code


;---------------------------------------------------------
; ANSI SGR (Select Graphic Rendition) color codes.
;
; Each is ESC[<n>m -- a fixed 5-byte sequence since all
; codes we use are 2 digits. reset_code returns to default
; terminal color/style.
;
; Wall / player / HUD / collectible colors are picked here
; so callers just say "set_color(COLOR_X)" and don't need
; to know escape sequence formatting.
;---------------------------------------------------------

color_wall_code   db 27, "[34m"      ; blue    -- maze walls
color_player_code db 27, "[93m"      ; yellow  -- player glyph
color_exit_code   db 27, "[92m"      ; green   -- exit tile
color_coin_code   db 27, "[93m"      ; yellow  -- coins
color_gem_code    db 27, "[96m"      ; cyan    -- gems
color_hud_code    db 27, "[97m"      ; white   -- HUD text
color_title_code  db 27, "[95m"      ; magenta -- splash/title text
color_breadcrumb_code db 27, "[90m"  ; black/dark gray -- visited tiles
color_hazard_code db 27, "[91m"      ; red     -- hazard tiles
reset_color_code  db 27, "[0m"

color_code_len equ 5
reset_color_len equ 4


section .bss

; Buffer used by print_char (single byte writes)
char_buffer resb 1

; Cursor movement buffer:  ESC[999;999H  (generous headroom)
cursor_buffer resb 32
row_buffer     resb 16
col_buffer     resb 16

; termios struct storage.
; struct termios on Linux x86-64 is 60 bytes:
;   c_iflag, c_oflag, c_cflag, c_lflag  (4 x 4 bytes)
;   c_line                              (1 byte)
;   c_cc[NCCS]                          (32 bytes, NCCS=32)
;   c_ispeed, c_ospeed                  (2 x 4 bytes)
; We store two copies: the original settings (to restore on
; exit) and a modified copy (to activate raw mode).
termios_orig resb 60
termios_raw  resb 60


section .text


global clear_screen
global print_char
global print_string
global move_cursor
global enable_raw_mode
global disable_raw_mode
global set_color
global reset_color

extern int_to_string


;=========================================================
; Linux ioctl request numbers (x86-64 asm-generic)
;=========================================================

TCGETS equ 0x5401
TCSETS equ 0x5402

; c_lflag bits we need to clear for raw mode
ICANON equ 0x0002
ECHO   equ 0x0008


;=========================================================
; Color selector codes, passed to set_color() in AL.
; Keeping these as small integers (rather than making
; callers know escape sequences) means game.asm/maze.asm/
; player.asm/main.asm never touch ANSI codes directly.
;=========================================================

COLOR_WALL   equ 0
COLOR_PLAYER equ 1
COLOR_EXIT   equ 2
COLOR_COIN   equ 3
COLOR_GEM    equ 4
COLOR_HUD    equ 5
COLOR_TITLE  equ 6
COLOR_BREADCRUMB equ 7
COLOR_HAZARD equ 8


;=========================================================
;
; clear_screen()
;
; Clears terminal screen and homes the cursor.
;
;=========================================================

clear_screen:

    mov rax,1                  ; syscall: write
    mov rdi,1                  ; fd: stdout
    lea rsi,[rel clear_code]
    mov rdx,clear_len
    syscall

    ret


;=========================================================
;
; print_char()
;
; Input:
;   AL = character to print
;
;=========================================================

print_char:

    mov [rel char_buffer],al

    mov rax,1
    mov rdi,1
    lea rsi,[rel char_buffer]
    mov rdx,1
    syscall

    ret


;=========================================================
;
; print_string()
;
; Prints a string of known length. This function owns its
; own syscall setup completely -- callers only need to set
; RSI/RDX, nothing is assumed left over from a previous call.
;
; Input:
;   RSI = string address
;   RDX = string length
;
;=========================================================

print_string:

    ; rax/rdi must be set explicitly every call -- never rely
    ; on register values left behind by a previous call.

    mov rax,1                  ; write syscall
    mov rdi,1                  ; stdout
    syscall

    ret


;=========================================================
;
; move_cursor(row,column)
;
; Input:
;   RDI = row
;   RSI = column
;
; Emits:  ESC[row;columnH
;
;=========================================================

move_cursor:

    push rdi
    push rsi

    ; Convert row number to string

    mov rax,rdi
    lea rdi,[rel row_buffer]
    call int_to_string

    ; Convert column number to string

    pop rsi
    mov rax,rsi
    lea rdi,[rel col_buffer]
    call int_to_string

    pop rdi

    ; Build ANSI escape sequence: ESC [ row ; column H

    lea rdi,[rel cursor_buffer]

    mov byte [rdi],27
    mov byte [rdi+1],'['

    lea rsi,[rel row_buffer]
    mov rcx,0

.copy_row:
    mov al,[rsi]
    cmp al,0
    je .row_done
    mov [rdi+2+rcx],al
    inc rsi
    inc rcx
    jmp .copy_row

.row_done:
    mov byte [rdi+2+rcx],';'
    inc rcx

    lea rsi,[rel col_buffer]

.copy_col:
    mov al,[rsi]
    cmp al,0
    je .col_done
    mov [rdi+2+rcx],al
    inc rsi
    inc rcx
    jmp .copy_col

.col_done:
    mov byte [rdi+2+rcx],'H'

    ; total length = ESC + [ + contents + H
    add rcx,3

    mov rax,1
    mov rdi,1
    lea rsi,[rel cursor_buffer]
    mov rdx,rcx
    syscall

    ret


;=========================================================
;
; set_color(color)
;
; Input:
;   AL = color selector (COLOR_WALL, COLOR_PLAYER, etc.)
;
; Writes the matching ANSI SGR escape sequence to stdout.
; All our codes are the same length (5 bytes: ESC [ NN m),
; so this is a straight lookup + fixed-length write rather
; than needing per-code length tracking.
;
; Unrecognized codes are silently ignored (no-op) rather
; than writing garbage -- callers are expected to only pass
; the COLOR_* constants.
;
;=========================================================

set_color:

    cmp al,COLOR_WALL
    je .wall
    cmp al,COLOR_PLAYER
    je .player
    cmp al,COLOR_EXIT
    je .exit_c
    cmp al,COLOR_COIN
    je .coin
    cmp al,COLOR_GEM
    je .gem
    cmp al,COLOR_HUD
    je .hud
    cmp al,COLOR_TITLE
    je .title
    cmp al,COLOR_BREADCRUMB
    je .breadcrumb
    cmp al,COLOR_HAZARD
    je .hazard

    ret

.wall:
    lea rsi,[rel color_wall_code]
    jmp .emit
.player:
    lea rsi,[rel color_player_code]
    jmp .emit
.exit_c:
    lea rsi,[rel color_exit_code]
    jmp .emit
.coin:
    lea rsi,[rel color_coin_code]
    jmp .emit
.gem:
    lea rsi,[rel color_gem_code]
    jmp .emit
.hud:
    lea rsi,[rel color_hud_code]
    jmp .emit
.title:
    lea rsi,[rel color_title_code]
    jmp .emit
.breadcrumb:
    lea rsi,[rel color_breadcrumb_code]
    jmp .emit
.hazard:
    lea rsi,[rel color_hazard_code]

.emit:
    mov rax,1
    mov rdi,1
    mov rdx,color_code_len
    syscall

    ret


;=========================================================
;
; reset_color()
;
; Returns terminal output to default color/style. Call
; after any colored output so unrelated text (or the shell
; prompt after quitting) doesn't inherit the last color.
;
;=========================================================

reset_color:

    mov rax,1
    mov rdi,1
    lea rsi,[rel reset_color_code]
    mov rdx,reset_color_len
    syscall

    ret


;=========================================================
;
; enable_raw_mode()
;
; Puts stdin into raw mode so keys are readable the instant
; they are pressed, with no Enter key required and no local
; echo. This is what makes WASD movement feel real-time
; instead of line-buffered.
;
; Saves the original settings first so they can be restored
; by disable_raw_mode() -- always call that before exiting,
; or the user's shell will be left in raw mode.
;
; Uses ioctl(fd, TCGETS/TCSETS, struct termios*)
;
;=========================================================

enable_raw_mode:

    push rbx

    ; --- fetch current terminal settings into termios_orig ---

    mov rax,16                 ; syscall: ioctl
    mov rdi,0                  ; fd: stdin
    mov rsi,TCGETS
    lea rdx,[rel termios_orig]
    syscall

    ; --- copy the 60-byte struct into termios_raw so we can
    ;     modify it without disturbing the saved original ---

    lea rsi,[rel termios_orig]
    lea rdi,[rel termios_raw]
    mov rcx,60

.copy_loop:
    mov al,[rsi]
    mov [rdi],al
    inc rsi
    inc rdi
    dec rcx
    jnz .copy_loop

    ; --- clear ICANON and ECHO in c_lflag ---
    ;
    ; struct layout: iflag(0) oflag(4) cflag(8) lflag(12)
    ; c_lflag is a 4-byte field at offset 12.

    lea rbx,[rel termios_raw]
    mov eax,[rbx+12]
    and eax, ~(ICANON | ECHO)
    mov [rbx+12],eax

    ; --- apply the modified settings ---

    mov rax,16                 ; ioctl
    mov rdi,0                  ; stdin
    mov rsi,TCSETS
    lea rdx,[rel termios_raw]
    syscall

    ; --- hide the blinking cursor while playing ---

    mov rax,1
    mov rdi,1
    lea rsi,[rel hide_cursor_code]
    mov rdx,hide_cursor_len
    syscall

    pop rbx
    ret


;=========================================================
;
; disable_raw_mode()
;
; Restores the terminal settings saved by enable_raw_mode().
; MUST be called before the program exits (including on the
; ESC-to-quit path), otherwise the user's shell keeps running
; in raw/no-echo mode after the game closes.
;
;=========================================================

disable_raw_mode:

    mov rax,16                 ; ioctl
    mov rdi,0                  ; stdin
    mov rsi,TCSETS
    lea rdx,[rel termios_orig]
    syscall

    ; --- clear the screen and home the cursor ---
    ;
    ; Without this, the cursor is left wherever gameplay last
    ; positioned it (e.g. mid-maze). The next shell prompt then
    ; prints from that leftover position instead of a fresh
    ; line, which looks fine by chance on some runs and produces
    ; visibly corrupted/overlapping output on others -- this is
    ; what caused the game to "draw messy" on repeated runs.

    mov rax,1
    mov rdi,1
    lea rsi,[rel clear_code]
    mov rdx,clear_len
    syscall

    ; --- show the cursor again ---

    mov rax,1
    mov rdi,1
    lea rsi,[rel show_cursor_code]
    mov rdx,show_cursor_len
    syscall

    ; --- reset color so the shell prompt isn't left tinted ---
    ; Without this, quitting mid-color-output leaves the
    ; terminal's default foreground color changed until the
    ; user runs `reset` or closes the tab -- same class of
    ; "messy on exit" bug as the missing clear-screen fix.

    mov rax,1
    mov rdi,1
    lea rsi,[rel reset_color_code]
    mov rdx,reset_color_len
    syscall

    ret

