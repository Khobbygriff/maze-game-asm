;=========================================================
; maze.asm
;=========================================================


section .data

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


level2_data:
    db "#############################"
    db "#P  #         #     #E      #"
    db "### ### ##### ### # ##### ###"
    db "# # #   #   #   # # #   #   #"
    db "# # # ### # ### # # # # ### #"
    db "# #   #   #   #   # # # #   #"
    db "# ##### ### ####### # # # # #"
    db "# #     #   #       # # # # #"
    db "# # # ##### # ####### # # # #"
    db "#   # #   # # #     # # # # #"
    db "# ### # # ### ### # # # # # #"
    db "#  X#   #         #   #   # #"
    db "#############################"

level2_width  equ 29
level2_height equ 13


level3_data:
    db "#######################################"
    db "#P  #X    #                 #         #"
    db "### ##### # ########### ### # ####### #"
    db "# # #   #       #       # # #       # #"
    db "# # # # ####### # ####### # # ##### # #"
    db "# #   #   #   # # #   # #   # #   #E# #"
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


level4_data:
    db "#########################################"
    db "#P  #         #     #             #     #"
    db "### ##### ### # # # ##### # ##### ### # #"
    db "# # #   #   #   # #     #   #   #     # #"
    db "# # # # ### ##### ##### ### # ######### #"
    db "# #   #   # # #   #   #   # #         # #"
    db "# ####### # #   ### # ### # ####### ### #"
    db "#       # #   #   # # #     #     #   # #"
    db "### ### # ####### # # ####### # # ### # #"
    db "#   #   #       #   #     # #   #     # #"
    db "# ############# # ####### # # # ##### # #"
    db "#             # # #   #   # # #     # # #"
    db "# ####### ## ## # ### # ### # ##### ### #"
    db "# #     #     # #     # #   # #     #   #"
    db "# ##### ##### # ####### # ### # ##### ###"
    db "# #     #E  # #         #     #       # #"
    db "# # ### ### # ########### ############# #"
    db "#   #       #                           #"
    db "#########################################"

level4_width  equ 41
level4_height equ 19


level_table:
    dq level1_data, level1_width, level1_height
    dq level2_data, level2_width, level2_height
    dq level3_data, level3_width, level3_height
    dq level4_data, level4_width, level4_height

LEVEL_DESCRIPTOR_SIZE equ 24
NUM_LEVELS             equ 4


start_rows: db 1, 1, 1, 1
start_cols: db 1, 1, 1, 1


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

COLOR_WALL equ 0
COLOR_EXIT equ 2
COLOR_COIN equ 3
COLOR_GEM  equ 4
COLOR_BREADCRUMB equ 7
COLOR_HAZARD equ 8


get_num_levels:

    mov al,NUM_LEVELS
    ret


load_level:

    mov rax,rdi
    mov rbx,LEVEL_DESCRIPTOR_SIZE
    mul rbx

    lea rbx,[rel level_table]
    add rbx,rax

    mov rcx,[rbx]
    mov [rel current_maze_ptr],rcx

    mov rcx,[rbx+8]
    mov [rel current_width],rcx

    mov rcx,[rbx+16]
    mov [rel current_height],rcx

    lea rbx,[rel start_rows]
    add rbx,rdi
    mov al,[rbx]

    lea rbx,[rel start_cols]
    add rbx,rdi
    mov ah,[rbx]

    ret


draw_maze:

    xor r8, r8

.row_loop:

    xor r9, r9

.column_loop:

    mov rax, r8
    mov rbx, [rel current_width]
    mul rbx
    add rax, r9

    mov rbx, [rel current_maze_ptr]
    mov al, [rbx + rax]

    cmp al,'P'
    jne .check_wall
    mov al,' '
    jmp .print_it

.check_wall:

    push rax

    cmp al,'#'
    je .colored_wall
    cmp al,'E'
    je .colored_exit
    cmp al,'X'
    je .colored_hazard

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

    pop rax

    mov rdi,r8
    mov rsi,r9
    call get_collectible_tile

    cmp al,1
    je .draw_coin
    cmp al,2
    je .draw_gem

    mov rax, r8
    mov rbx, [rel current_width]
    mul rbx
    add rax, r9
    mov rbx, [rel current_maze_ptr]
    mov al, [rbx + rax]

    push rax
    mov rdi,r8
    mov rsi,r9
    call is_visited
    pop rax

    cmp al,1
    je .draw_breadcrumb

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

    mov al, 10
    call print_char

    inc r8
    mov rbx,[rel current_height]
    cmp r8, rbx
    jl .row_loop

    ret


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