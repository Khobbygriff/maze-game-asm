;=========================================================
; utils.asm
;
; General utility functions
;
; Functions:
;
;   int_to_string()
;
;=========================================================

section .bss

number_buffer resb 32


section .text


global int_to_string



;=========================================================
;
; int_to_string()
;
; Converts an integer into ASCII characters.
;
; Input:
;
;   RAX = number to convert
;   RDI = address of output buffer
;
; Output:
;
;   Buffer contains ASCII representation
;
; Example:
;
;   RAX = 123
;
;   Output:
;
;   "123"
;
;=========================================================


int_to_string:


    ; Save registers that we modify

    push rbx
    push rcx
    push rdx
    push rsi



    ;------------------------------------------
    ; Special case:
    ; If number is zero
    ;------------------------------------------

    cmp rax,0
    jne convert_number


    mov byte [rdi],'0'
    mov byte [rdi+1],0

    jmp conversion_done




convert_number:


    ; rsi will point to temporary storage

    mov rsi,rdi

    add rsi,20


    ; Null terminate

    mov byte [rsi],0


    ; Move backwards through buffer

    dec rsi



convert_loop:


    ; Divide number by 10
    ;
    ; remainder = next digit

    xor rdx,rdx

    mov rbx,10

    div rbx



    ; Convert remainder to ASCII

    add dl,'0'


    ; Store digit

    mov [rsi],dl


    ; Move backwards

    dec rsi



    ; Continue if quotient is not zero

    cmp rax,0

    jne convert_loop



    ;------------------------------------------
    ; Copy result to output buffer
    ;------------------------------------------


    inc rsi


copy_loop:


    mov al,[rsi]

    mov [rdi],al


    cmp al,0

    je conversion_done


    inc rsi

    inc rdi


    jmp copy_loop




conversion_done:


    pop rsi
    pop rdx
    pop rcx
    pop rbx


    ret
