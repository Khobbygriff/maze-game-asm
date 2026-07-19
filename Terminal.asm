;=========================================================
; terminal.asm
;=========================================================


section .data

clear_code db 27, "[2J", 27, "[H"
clear_len  equ $ - clear_code

hide_cursor_code db 27, "[?25l"
hide_cursor_len  equ $ - hide_cursor_code

show_cursor_code db 27, "[?25h"
show_cursor_len  equ $ - show_cursor_code

color_wall_code   db 27, "[34m"
color_player_code db 27, "[93m"
color_exit_code   db 27, "[92m"
color_coin_code   db 27, "[93m"
color_gem_code    db 27, "[96m"
color_hud_code    db 27, "[97m"
color_title_code  db 27, "[95m"
color_breadcrumb_code db 27, "[90m"
color_hazard_code db 27, "[91m"
reset_color_code  db 27, "[0m"

color_code_len equ 5
reset_color_len equ 4


section .bss

char_buffer resb 1

cursor_buffer resb 32
row_buffer     resb 16
col_buffer     resb 16

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


TCGETS equ 0x5401
TCSETS equ 0x5402

ICANON equ 0x0002
ECHO   equ 0x0008


COLOR_WALL   equ 0
COLOR_PLAYER equ 1
COLOR_EXIT   equ 2
COLOR_COIN   equ 3
COLOR_GEM    equ 4
COLOR_HUD    equ 5
COLOR_TITLE  equ 6
COLOR_BREADCRUMB equ 7
COLOR_HAZARD equ 8


clear_screen:

    mov rax,1
    mov rdi,1
    lea rsi,[rel clear_code]
    mov rdx,clear_len
    syscall

    ret


print_char:

    ; Only AL (the character to print) is documented as this
    ; function's input -- callers should be free to hold
    ; anything they like in rdi/rsi/rdx/rcx across a call to
    ; this. Two separate things threaten that:
    ;
    ; 1. The write() syscall setup below needs rdi=1 (stdout
    ;    fd), rsi=&char_buffer, and rdx=1, which were being
    ;    written directly into those registers with no
    ;    save/restore. move_cursor already saves/restores
    ;    rdi/rsi around its own internal use of them for
    ;    exactly this reason; this function needs the same.
    ;
    ; 2. The `syscall` instruction itself unconditionally
    ;    clobbers rcx and r11 as part of the x86-64 SYSCALL/
    ;    SYSRET ABI (rcx holds the return address, r11 holds
    ;    flags) -- independent of what the syscall body does.
    ;    This is the same clobbering documented elsewhere in
    ;    this codebase (a value stashed in r11 across a call
    ;    that executes `syscall` is destroyed); here it hit
    ;    rcx instead.
    ;
    ; Together these silently corrupted main.asm's highscore
    ; name-printing loop: rdi (the read pointer into the name
    ; buffer) and rcx (the remaining-character countdown) were
    ; both live across `call print_char`, and both got
    ; clobbered by the very first call -- rdi to 1, rcx to
    ; whatever syscall left behind. The loop then dereferenced
    ; an unmapped low address on its next iteration and
    ; segfaulted (reproduced firsthand: "Enter your name: Hope"
    ; -> splash screen -> "1. H" -> Segmentation fault).

    push rdi
    push rsi
    push rdx
    push rcx
    push r11

    mov [rel char_buffer],al

    mov rax,1
    mov rdi,1
    lea rsi,[rel char_buffer]
    mov rdx,1
    syscall

    pop r11
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    ret


print_string:

    mov rax,1
    mov rdi,1
    syscall

    ret


move_cursor:

    push rdi
    push rsi

    mov rax,rdi
    lea rdi,[rel row_buffer]
    call int_to_string

    pop rsi
    mov rax,rsi
    lea rdi,[rel col_buffer]
    call int_to_string

    pop rdi

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

    add rcx,3

    mov rax,1
    mov rdi,1
    lea rsi,[rel cursor_buffer]
    mov rdx,rcx
    syscall

    ret


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


reset_color:

    mov rax,1
    mov rdi,1
    lea rsi,[rel reset_color_code]
    mov rdx,reset_color_len
    syscall

    ret


enable_raw_mode:

    push rbx

    mov rax,16
    mov rdi,0
    mov rsi,TCGETS
    lea rdx,[rel termios_orig]
    syscall

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

    lea rbx,[rel termios_raw]
    mov eax,[rbx+12]
    and eax, ~(ICANON | ECHO)
    mov [rbx+12],eax

    mov rax,16
    mov rdi,0
    mov rsi,TCSETS
    lea rdx,[rel termios_raw]
    syscall

    mov rax,1
    mov rdi,1
    lea rsi,[rel hide_cursor_code]
    mov rdx,hide_cursor_len
    syscall

    pop rbx
    ret


disable_raw_mode:

    mov rax,16
    mov rdi,0
    mov rsi,TCSETS
    lea rdx,[rel termios_orig]
    syscall

    mov rax,1
    mov rdi,1
    lea rsi,[rel clear_code]
    mov rdx,clear_len
    syscall

    mov rax,1
    mov rdi,1
    lea rsi,[rel show_cursor_code]
    mov rdx,show_cursor_len
    syscall

    mov rax,1
    mov rdi,1
    lea rsi,[rel reset_color_code]
    mov rdx,reset_color_len
    syscall

    ret