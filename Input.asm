;=========================================================
; input.asm
;
; Keyboard input handling
;
; Functions:
;
;   read_key()
;
;=========================================================


section .bss


; Stores one key

key_buffer resb 1

; Scratch single-byte buffer used by read_line's per-char
; reads. Separate from key_buffer so read_line doesn't
; collide with read_key if anything ever interleaves them.
line_char_buffer resb 1


section .text


global read_key
global read_line



;=========================================================
;
; read_key()
;
; Reads one character from keyboard.
;
; Output:
;
;   AL = pressed key
;
;=========================================================


read_key:


    ; Linux syscall:
    ;
    ; read(fd, buffer, size)
    ;
    ; rax = 0
    ; rdi = stdin
    ; rsi = buffer
    ; rdx = size
    ;


    mov rax,0          ; read syscall

    mov rdi,0          ; stdin

    lea rsi,[rel key_buffer]

    mov rdx,1

    syscall



    ; Return character

    mov al,[rel key_buffer]


    ret


;=========================================================
;
; read_line(buffer, max_len)
;
; Reads a line of text from stdin, one byte at a time,
; stopping at newline or when max_len-1 characters have
; been read (always leaves room for the null terminator).
; Null-terminates the buffer.
;
; MUST be called before enable_raw_mode() -- this relies on
; the terminal's normal canonical-mode line editing
; (backspace, local echo) rather than implementing its own,
; since raw mode disables both of those. Calling this after
; raw mode is enabled would mean no visible echo and no
; backspace support while the user types.
;
; Input:
;
;   RDI = buffer address
;   RSI = max buffer size (including null terminator)
;
; Output:
;
;   Buffer contains null-terminated string (newline, if any,
;   is stripped and not included)
;
;=========================================================

read_line:

    push rbx
    push r12
    push r13

    mov r12,rdi         ; r12 = buffer pointer (write cursor)
    mov r13,rsi         ; r13 = max size
    dec r13             ; reserve 1 byte for null terminator
    xor rbx,rbx         ; rbx = chars written so far

.read_loop:

    cmp rbx,r13
    jge .terminate       ; buffer full -- stop reading

    mov rax,0            ; read syscall
    mov rdi,0             ; stdin
    lea rsi,[rel line_char_buffer]
    mov rdx,1
    syscall

    cmp rax,1
    jne .terminate        ; EOF or read error -- stop

    mov al,[rel line_char_buffer]

    cmp al,10              ; newline ends the line
    je .terminate
    cmp al,13               ; carriage return also ends it
    je .terminate

    mov [r12+rbx],al
    inc rbx
    jmp .read_loop

.terminate:

    mov byte [r12+rbx],0

    pop r13
    pop r12
    pop rbx

    ret
