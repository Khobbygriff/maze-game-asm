;=========================================================
; game.asm
;=========================================================


section .data

game_state db 0

level_index db 0

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


COLLECTIBLE_TYPE_COIN equ 0
COLLECTIBLE_TYPE_GEM  equ 1
COLLECTIBLES_PER_LEVEL equ 4
COLLECTIBLE_ENTRY_SIZE equ 3

COIN_SCORE equ 10
GEM_SCORE  equ 25
HAZARD_PENALTY equ 50

; Must be >= the tile count of the largest level in maze.asm's
; level_table (width * height). Currently that's level 4 at
; 41x19 = 779. This was previously hardcoded as 663 (level 3's
; 39x17), which was correct only until level 4 was added --
; mark_visited/is_visited index this buffer as row*width+col,
; so once current_width/current_height exceeded 663 tiles, any
; visited tile past index 662 wrote one byte past the end of
; this buffer into whatever .bss symbol happens to follow it.
; If a larger level is ever added, this constant must grow to
; match, and reset_breadcrumbs' clear loop (which reads this
; same constant) will follow automatically.
BREADCRUMB_MAP_SIZE equ 779

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

level4_collectibles:
    db 4,17,COLLECTIBLE_TYPE_COIN
    db 11,33,COLLECTIBLE_TYPE_GEM
    db 1,16,COLLECTIBLE_TYPE_COIN
    db 3,30,COLLECTIBLE_TYPE_GEM

collectible_table:
    dq level1_collectibles
    dq level2_collectibles
    dq level3_collectibles
    dq level4_collectibles


section .bss

collected_flags resb COLLECTIBLES_PER_LEVEL

highscore_table resb HIGHSCORE_FILE_SIZE

breadcrumb_map resb BREADCRUMB_MAP_SIZE

move_count resq 1

score resq 1

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

extern get_num_levels


check_win:

    movzx rdi,byte [rel player_row]
    movzx rsi,byte [rel player_col]

    call get_tile

    cmp al,'E'
    jne .not_won

    mov byte [rel game_state],1

.not_won:

    ret


get_game_state:

    mov al,[rel game_state]
    ret


reset_game_state:

    mov byte [rel game_state],0
    mov qword [rel move_count],0

    xor rax,rax
    mov rcx,COLLECTIBLES_PER_LEVEL
    lea rdi,[rel collected_flags]

.clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .clear_loop

    call reset_breadcrumbs

    movzx rax,byte [rel level_index]
    mov rcx,8
    mul rcx

    lea rbx,[rel collectible_table]
    add rbx,rax

    mov rcx,[rbx]
    mov [rel current_collectible_table],rcx

    ret


current_level_index:

    mov al,[rel level_index]
    ret


advance_level:

    call get_num_levels
    dec al

    cmp [rel level_index],al
    jge .no_more_levels

    inc byte [rel level_index]
    mov al,1
    ret

.no_more_levels:

    mov byte [rel game_state],2
    mov al,0
    ret


record_move:

    inc qword [rel move_count]
    ret


get_move_count:

    mov rax,[rel move_count]
    ret


get_score:

    mov rax,[rel score]
    ret


add_score:

    add [rel score],rdi
    ret


check_collect:

    push rbx
    push r12
    push r13
    push r14

    movzx r12,byte [rel player_row]
    movzx r13,byte [rel player_col]

    mov r14,[rel current_collectible_table]

    xor rcx,rcx

.check_loop:

    cmp rcx,COLLECTIBLES_PER_LEVEL
    jge .done

    lea rbx,[rel collected_flags]
    cmp byte [rbx+rcx],0
    jne .next_item

    mov rax,rcx
    imul rax,COLLECTIBLE_ENTRY_SIZE
    add rax,r14

    movzx rbx,byte [rax]
    cmp rbx,r12
    jne .next_item

    movzx rbx,byte [rax+1]
    cmp rbx,r13
    jne .next_item

    lea rbx,[rel collected_flags]
    mov byte [rbx+rcx],1

    movzx rbx,byte [rax+2]
    cmp rbx,COLLECTIBLE_TYPE_GEM
    je .award_gem

    mov rdi,COIN_SCORE
    jmp .award

.award_gem:

    mov rdi,GEM_SCORE

.award:

    call add_score
    jmp .done

.next_item:

    inc rcx
    jmp .check_loop

.done:

    pop r14
    pop r13
    pop r12
    pop rbx

    ret


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

    movzx rbx,byte [rax+2]
    cmp rbx,COLLECTIBLE_TYPE_GEM
    je .is_gem

    mov al,1
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


load_highscores:

    push rbx
    push r12
    push r13

    mov rax,2
    mov rdi,highscore_filename
    mov rsi,0
    mov rdx,0
    syscall

    cmp rax,0
    jl .file_not_found

    mov r12,rax

    mov rax,0
    mov rdi,r12
    lea rsi,[rel highscore_table]
    mov rdx,HIGHSCORE_FILE_SIZE
    syscall

    mov r13,rax

    mov rax,3
    mov rdi,r12
    syscall

    cmp r13,HIGHSCORE_FILE_SIZE
    jge .done

.file_not_found:

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


save_highscores:

    push rbx
    push r12

    mov rax,2
    mov rdi,highscore_filename
    mov rsi,0x241
    mov rdx,0o644
    syscall

    cmp rax,0
    jl .done

    mov r12,rax

    mov rax,1
    mov rdi,r12
    lea rsi,[rel highscore_table]
    mov rdx,HIGHSCORE_FILE_SIZE
    syscall

    mov rax,3
    mov rdi,r12
    syscall

.done:

    pop r12
    pop rbx
    ret


insert_highscore:

    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12,rdi
    mov r13,rsi

    lea rbx,[rel highscore_table]
    add rbx,(HIGHSCORE_NUM_RECORDS - 1) * HIGHSCORE_RECORD_SIZE
    add rbx,HIGHSCORE_NAME_MAX

    mov r14,[rbx]

    cmp r14,0
    je .insert_needed

    cmp r13,r14
    jle .done

.insert_needed:

    xor r15,r15

.find_loop:

    cmp r15,HIGHSCORE_NUM_RECORDS
    je .insert_at_end

    lea rbx,[rel highscore_table]
    mov rax,r15
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax
    add rbx,HIGHSCORE_NAME_MAX

    mov r14,[rbx]

    cmp r14,0
    je .insert_here

    cmp r13,r14
    jg .insert_here

    inc r15
    jmp .find_loop

.insert_at_end:

    mov r15,HIGHSCORE_NUM_RECORDS - 1

.insert_here:

    ; Shift records down from the bottom of the table upward
    ; toward the insertion point r15, one slot each. This must
    ; iterate bottom-up (source index walking DOWN from
    ; NUM_RECORDS-2 to r15): shifting top-down instead
    ; (starting at r15 and copying r15+1 -> r15, then
    ; incrementing r15) overwrites the very slot being
    ; inserted into with the record below it and drags the
    ; insertion index itself to the bottom of the table --
    ; that was the original bug, where a single insert into an
    ; empty table landed in record 2 instead of record 0.

    cmp r15,HIGHSCORE_NUM_RECORDS - 1
    je .no_shift

    mov r14,HIGHSCORE_NUM_RECORDS - 2   ; last movable source index

.shift_loop:

    cmp r14,r15
    jl .no_shift                        ; done once source < insertion point

    lea rbx,[rel highscore_table]
    mov rax,r14
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax                          ; rbx = source record (r14)

    lea rcx,[rel highscore_table]
    mov rdx,r14
    inc rdx
    imul rdx,HIGHSCORE_RECORD_SIZE
    add rcx,rdx                          ; rcx = dest record (r14+1)

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

    dec r14
    jmp .shift_loop

.no_shift:

    lea rbx,[rel highscore_table]
    mov rax,r15
    imul rax,HIGHSCORE_RECORD_SIZE
    add rbx,rax

    mov rdi,rbx
    mov rsi,r12
    mov rcx,HIGHSCORE_NAME_MAX
    xor rdx,rdx

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

.pad_loop:

    cmp rdx,HIGHSCORE_NAME_MAX
    jge .name_done

    mov byte [rdi],0
    inc rdi
    inc rdx
    jmp .pad_loop

.name_done:

    add rbx,HIGHSCORE_NAME_MAX
    mov [rbx],r13

.done:

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


restart_level:

    push rbx
    push r12

    call current_level_index
    movzx rdi,al

    call load_level

    mov cl,ah
    mov dil,al
    mov sil,cl
    call spawn_player

    mov qword [rel move_count],0

    xor rax,rax
    mov rcx,COLLECTIBLES_PER_LEVEL
    lea rdi,[rel collected_flags]

.clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .clear_loop

    call reset_breadcrumbs

    pop r12
    pop rbx
    ret


reset_breadcrumbs:

    push rbx
    push rcx

    xor rax,rax
    mov rcx,BREADCRUMB_MAP_SIZE
    lea rdi,[rel breadcrumb_map]

.bc_clear_loop:
    mov byte [rdi],0
    inc rdi
    dec rcx
    jnz .bc_clear_loop

    pop rcx
    pop rbx
    ret


mark_visited:

    push rbx
    push rcx

    mov rax,rdi
    mov rbx,[rel current_width]
    mul rbx
    add rax,rsi

    lea rbx,[rel breadcrumb_map]
    mov byte [rbx+rax],1

    pop rcx
    pop rbx
    ret


is_visited:

    push rbx

    mov rax,rdi
    mov rbx,[rel current_width]
    mul rbx
    add rax,rsi

    lea rbx,[rel breadcrumb_map]
    mov al,[rbx+rax]

    pop rbx
    ret


check_hazard:

    push rbx
    push r12
    push r13

    movzx rdi,byte [rel player_row]
    movzx rsi,byte [rel player_col]

    call get_tile

    cmp al,'X'
    jne .no_hazard

    mov rax,[rel score]
    cmp rax,HAZARD_PENALTY
    jge .deduct

    mov qword [rel score],0
    jmp .reset_position

.deduct:

    sub rax,HAZARD_PENALTY
    mov [rel score],rax

.reset_position:

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


set_level_index:

    mov [rel level_index],dil
    ret


reset_score:

    mov qword [rel score],0
    ret