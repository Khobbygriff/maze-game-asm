;=========================================================
; maze.asm
;
; Contains:
;   - Maze data for multiple levels
;   - Maze rendering function
;   - Tile lookup function
;
; The maze is stored as ASCII characters.
;
; Symbols:
;
;   # = Wall
;   P = Player starting position (visual marker only --
;       actual start coords come from the level table below)
;   E = Exit
;   Space = Empty path
;
; ---------------------------------------------------------
; Multi-level design
; ---------------------------------------------------------
;
; Rather than one hardcoded maze, we keep an array of level
; "descriptors". Each descriptor is 24 bytes:
;
;   offset 0  : pointer to the maze character data (8 bytes)
;   offset 8  : width               (qword)
;   offset 16 : height              (qword)
;
; and a matching entry (by index) in start_positions for the
; player's spawn row/col on that level.
;
; This is what makes "multiple levels" possible: main.asm
; just increments a level index and reloads everything from
; this table -- no code duplication per level.
;
;=========================================================


section .data


;----------------------------------------------------------
; Level 1 -- small, easy
;
; All three mazes below were generated with a randomized
; depth-first "carve" algorithm (see tools/gen_mazes.py
; description in the project notes) and verified solvable
; with a breadth-first search from P to E before being
; hand-transcribed here. This guarantees -- rather than
; hopes -- that every level can actually be completed, and
; that every row has exactly `width` characters (a maze
; with inconsistent row lengths silently corrupts the
; row*width+column indexing used by draw_maze/get_tile).
;----------------------------------------------------------

level1_data:
    db "#####################"
    db "#P#     #   #       #"
    db "# # ### # # # ##### #"
    db "# #  E#   #       # #"
    db "# ################# #"
    db "#     #   #       # #"
    db "##### # # # ##### # #"
    db "#       #   #       #"
    db "#####################"

level1_width  equ 21
level1_height equ 9


;----------------------------------------------------------
; Level 2 -- medium, longer path (100-move shortest path)
;----------------------------------------------------------

level2_data:
    db "#############################"
    db "#P  #         #     #E      #"
    db "### ### ##### ### # ##### ###"
    db "# # #   #   #   # # #   #   #"
    db "# # # ### # ### # # # # ### #"
    db "# #   #   #   # X # # # #   #"
    db "# ##### ### ####### # # # # #"
    db "# #     #   #       # # # # #"
    db "# # # ##### # ####### # # # #"
    db "#   # #   # # #     # # # # #"
    db "# ### # # ### ### # # # # # #"
    db "#   #   #         #   #   # #"
    db "#############################"

level2_width  equ 29
level2_height equ 13


;----------------------------------------------------------
; Level 3 -- largest, hardest (146-move shortest path)
;----------------------------------------------------------

level3_data:
    db "#######################################"
    db "#P  #     #                 #         #"
    db "### ##### # ########### ### # ####### #"
    db "# # #   #       #       # # #       # #"
    db "# # # # ####### # ####### # # ##### # #"
    db "# #   #   #   # # # X # #   # #   #E# #"
    db "# ####### # ### # # # # # ##### # ### #"
    db "#       # #     # # # #         #   # #"
    db "####### # ####### # # ############# # #"
    db "#       #       #   #     #       # # #"
    db "# ############# # ####### ##### # # # #"
    db "#   #       # X # #   #   #     # # # #"
    db "### # ### # # # # ### # ### ####### # #"
    db "#   #   # #   # #     # #         # # #"
    db "# ##### # ##### ####### # ####### # # #"
    db "#       #               #       #     #"
    db "#######################################"

level3_width  equ 39
level3_height equ 17


;----------------------------------------------------------
; Level table
;
; Each entry: dq maze_ptr, dq width, dq height
;----------------------------------------------------------

level_table:
    dq level1_data, level1_width, level1_height
    dq level2_data, level2_width, level2_height
    dq level3_data, level3_width, level3_height

LEVEL_DESCRIPTOR_SIZE equ 24
NUM_LEVELS             equ 3


;----------------------------------------------------------
; Player start position per level (row, col), matching the
; 'P' marker placed in each maze above. All three generated
; mazes place P at (1,1) since the carve algorithm always
; begins there, but this table exists so that isn't a
; hardcoded assumption elsewhere in the code -- a future
; hand-authored or differently-generated level could start
; anywhere without touching player.asm or main.asm.
;----------------------------------------------------------

start_rows: db 1, 1, 1
start_cols: db 1, 1, 1


;----------------------------------------------------------
; Current level's runtime data (filled in by load_level)
;----------------------------------------------------------

section .bss

current_maze_ptr resq 1
current_width    resq 1
current_height   resq 1


section .text


global draw_maze
global get_tile
global load_level
global get_num_levels
global current_width
global current_height

extern print_char
extern set_color
extern reset_color
extern get_collectible_tile
extern is_visited

; Mirror of the COLOR_* constants defined in terminal.asm.
; NASM `equ` constants don't cross files, so this is
; redeclared here rather than shared -- values must stay
; in sync with terminal.asm's COLOR_WALL/COLOR_EXIT/etc.
COLOR_WALL equ 0
COLOR_EXIT equ 2
COLOR_COIN equ 3
COLOR_GEM  equ 4
COLOR_BREADCRUMB equ 7
COLOR_HAZARD equ 8


;=========================================================
;
; get_num_levels()
;
; Output:
;
;   AL = total number of levels in level_table
;
; Exists so other modules (game.asm) don't need to
; duplicate the NUM_LEVELS constant.
;
;=========================================================

get_num_levels:

    mov al,NUM_LEVELS
    ret


;=========================================================
;
; load_level(level_index)
;
; Loads level metadata (pointer/width/height) from the
; level table into the current_* variables used by
; draw_maze and get_tile. Also returns the start row/col
; for the caller to place the player.
;
; Input:
;
;   RDI = level index (0-based)
;
; Output:
;
;   AL  = start row
;   AH  = start col
;
;=========================================================

load_level:

    ; index into level_table: index * LEVEL_DESCRIPTOR_SIZE

    mov rax,rdi
    mov rbx,LEVEL_DESCRIPTOR_SIZE
    mul rbx

    lea rbx,[rel level_table]
    add rbx,rax

    mov rcx,[rbx]           ; maze pointer
    mov [rel current_maze_ptr],rcx

    mov rcx,[rbx+8]         ; width
    mov [rel current_width],rcx

    mov rcx,[rbx+16]        ; height
    mov [rel current_height],rcx

    ; fetch start row/col for this level index

    lea rbx,[rel start_rows]
    add rbx,rdi
    mov al,[rbx]

    lea rbx,[rel start_cols]
    add rbx,rdi
    mov ah,[rbx]

    ret


;=========================================================
;
; draw_maze()
;
; Loops through the current level's maze array and prints
; every character.
;
; Registers:
;
;   r8  = current row
;   r9  = current column
;   r10 = maze index
;
;=========================================================


draw_maze:

    xor r8, r8                     ; row = 0

.row_loop:

    xor r9, r9                     ; column = 0

.column_loop:

    ; index = row * width + column

    mov rax, r8
    mov rbx, [rel current_width]
    mul rbx
    add rax, r9

    ; load character from maze array

    mov rbx, [rel current_maze_ptr]
    mov al, [rbx + rax]

    ; the 'P' marker is only for humans reading the source;
    ; render it as empty space since the player sprite is
    ; drawn separately by draw_player()

    cmp al,'P'
    jne .check_wall
    mov al,' '
    jmp .print_it

.check_wall:

    ; Stash the tile char on the stack across set_color/
    ; reset_color calls. NOTE: a register is NOT safe here,
    ; even a caller-saved one like r11 -- set_color/reset_color
    ; execute a real `syscall` instruction, and the x86-64
    ; syscall ABI *always* clobbers RCX and R11 (the CPU uses
    ; them to hold the return address and flags for SYSRET).
    ; This bit us once already stashing a key in AH across a
    ; call; same failure mode, different register. The stack
    ; is always safe since neither syscall nor our own
    ; functions touch RSP except via matched push/pop.

    push rax

    cmp al,'#'
    je .colored_wall
    cmp al,'E'
    je .colored_exit
    cmp al,'X'
    je .colored_hazard

    ; plain tile -- might still have an uncollected coin/gem
    ; sitting on it, so route through a check rather than
    ; printing directly

    jmp .plain_tile

.colored_wall:

    mov al,COLOR_WALL
    call set_color
    pop rax
    call print_char
    call reset_color
    jmp .after_print

.colored_exit:

    mov al,COLOR_EXIT
    call set_color
    pop rax
    call print_char
    call reset_color
    jmp .after_print

.colored_hazard:

    mov al,COLOR_HAZARD
    call set_color
    pop rax
    call print_char
    call reset_color
    jmp .after_print

.plain_tile:

    ; discard the stashed char -- get_collectible_tile clobbers
    ; rax/rcx/rdi/rsi (r8/r9/r10, the real loop counters, are
    ; untouched by it, so this is safe to call directly). We
    ; recompute the plain character afterward rather than try
    ; to preserve it across the call.

    pop rax

    mov rdi,r8
    mov rsi,r9
    call get_collectible_tile

    cmp al,1
    je .draw_coin
    cmp al,2
    je .draw_gem

    ; no item here -- recompute and check if visited

    mov rax, r8
    mov rbx, [rel current_width]
    mul rbx
    add rax, r9
    mov rbx, [rel current_maze_ptr]
    mov al, [rbx + rax]

    ; Check if this tile has been visited

    push rax
    mov rdi,r8
    mov rsi,r9
    call is_visited
    pop rax

    cmp al,1
    je .draw_breadcrumb

    ; Not visited - print plain character

    jmp .print_it

.draw_breadcrumb:

    mov al,COLOR_BREADCRUMB
    call set_color
    mov al,' '
    call print_char
    call reset_color
    jmp .after_print

.draw_coin:

    mov al,COLOR_COIN
    call set_color
    mov al,'o'
    call print_char
    call reset_color
    jmp .after_print

.draw_gem:

    mov al,COLOR_GEM
    call set_color
    mov al,'*'
    call print_char
    call reset_color
    jmp .after_print

.print_it:

    call print_char

.after_print:

    inc r9
    mov rbx,[rel current_width]
    cmp r9, rbx
    jl .column_loop

    ; end of row -- newline

    mov al, 10
    call print_char

    inc r8
    mov rbx,[rel current_height]
    cmp r8, rbx
    jl .row_loop

    ret


;=========================================================
;
; get_tile(row,column)
;
; Returns the character at a maze position in the current
; level.
;
; Input:
;
;   RDI = row
;   RSI = column
;
; Output:
;
;   AL = character
;
; If outside maze bounds, AL = '#' (treated as a wall).
;
;=========================================================


get_tile:

    cmp rdi,0
    jl .outside

    mov rax,[rel current_height]
    cmp rdi,rax
    jae .outside

    cmp rsi,0
    jl .outside

    mov rax,[rel current_width]
    cmp rsi,rax
    jae .outside

    ; index = row * width + column

    mov rax,rdi
    mov rbx,[rel current_width]
    mul rbx
    add rax,rsi

    mov rbx,[rel current_maze_ptr]
    mov al,[rbx+rax]

    ret

.outside:

    mov al,'#'
    ret
