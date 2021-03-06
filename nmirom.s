        ;
        ; HACK menu (an NMI trigger menu for M4 board)
        ; Written by Duke 2018/2019 - http://www.spinpoint.org
        ;
        ; Assemble with RASM assembler from http://www.roudoudou.com/rasm/
        ; into nmirom.bin and use M4 firmware "dev version" (M4FIRM_dev_version.zip) to load it from root of microSD card
        ;

C_OPEN						equ 0x4301
C_READ						equ 0x4302
C_READ2						equ 0x4312
C_WRITE						equ 0x4303
C_RENAME					equ 0x430F
C_WRITE2					equ 0x431B
C_COPYFILE2					equ 0x431C
C_CLOSE						equ 0x4304
C_SEEK						equ 0x4305
C_READDIR					equ	0x4306
C_NMIOFF					equ 0x4319
C_ROMWRITE					equ	0x43FD
FA_READ 					equ	1
FA_WRITE					equ	2
FA_CREATE_NEW				equ 4
FA_CREATE_ALWAYS			equ 8
FA_OPEN_ALWAYS				equ 16
FA_REALMODE					equ 128
DATAPORT                    equ 0xFE00
ACKPORT                     equ 0xFC00
;snamem equ 0xF300

; screen layout (column<<8)|line
L_MAINTITLE                 equ (51<<8)|24
L_Z80_REGSTITLE             equ (L_Z80_REGS_X<<8)|L_Z80_REGS_Y
L_Z80_REGS_X                equ 60
L_Z80_REGS_Y                equ 7

L_HW_REGS_X                 equ 0
L_HW_REGS_Y                 equ 7

L_HW_REGSHEADER             equ (L_HW_REGS_X+6<<8)|L_HW_REGS_Y
L_HW_REGS                   equ (L_HW_REGS_X<<8)|L_HW_REGS_Y+2

L_HW_RMR_MMR_ROM_X          equ 60
L_HW_RMR_MMR_ROM_Y          equ 18

L_HW_PPI_X                  equ 71
L_HW_PPI_Y                  equ 18

L_KEYBOARDTYPE              equ (60<<8)|20

L_MENU_X                    equ 0
L_MENU_Y                    equ 13
L_MENU                      equ (L_MENU_X+3<<8)|L_MENU_Y

L_SAVESNAPSHOT              equ (0<<8)|23
I_SAVESNAPSHOT              equ (16<<8)|60	; xpos=16, max_len = 60
L_SAVING                    equ (0<<8)|24

L_LOADSNAPSHOT              equ (0<<8)|23
I_LOADSNAPSHOT              equ (16<<8)|60	; xpos=16, max_len = 60
L_LOADING                   equ (0<<8)|24

L_DUMPSIZE                  equ (L_MENU_X+3+20<<8)|L_MENU_Y+2

L_POKEADDRESS               equ (0<<8)|23
I_POKEADDRESS               equ (6<<8)|4	; xpos=6, max_len = 4
L_POKEVAL                   equ (12<<8)|23
I_POKEVAL                   equ (17<<8)|2	; xpos=16, max_len = 2
L_POKEAPPLIED               equ (0<<8)|24

L_DISPMEM                   equ (0<<8)|23
I_DISPMEM                   equ (6<<8)|4	; xpos=6, max_len = 4
L_DISPMEMDUMP               equ (0<<8)|0
N_DISPMEM                   equ 6
N_DISPMEMBYTES              equ N_DISPMEM*16

        org	0x0
m4romnum: db 6
keyb_layout: db 0
        
        org	0x38
        ld a,1
        ret
        
        org 0x66
nmi:	jp main
        org 0x100		
        ; sna header
sna_header:	db "MV - SNA"
unused:		ds 8,0
version:	db 1
cpu_regs:	ds 29,0
ga_pen:		db 0
palette:	ds 17,0
ga_multi:	db 0
ramconf:	db 0
crtc_sel:	db 0
crtc_regs:	ds 18,0
romsel:		db 0
ppiA:		db 0
ppiB:		db 0
ppiC:		db 0
ppiCtrl:	db 0
psg_sel:	db 0
psg_regs:	ds 16,0
memdump_sz: db 0
reserved:	ds 116,0
m4snaident: db "M4 Board by Duke"
            ds 16,0

        ; at entry
        ; lowerrom is force enabled in romCore logic, until next RMR write
        ; ramdis & romdis is asserted in read from 0-0x3FFF
main:
        ; store regs
        ld (0xFFFE),sp	; 0xFFFE
        ld sp,0xFFFC
        push hl			; 0xFFFA
        push de			; 0xFFF8
        push bc			; 0xFFF6
        push af			; 0xFFF4
        ld	a,r
        push af			; 0xFFF2
        ld	a,i
        push af			; 0xFFF0
        ld a,(m4romnum)
        ld	bc, 0xDF00
        out (c),a			; select M4 rom
        ;
        ; first write to RMR, enables lowerrom, so we are no longer executing from RAMDIS "ram" mode
        ;
        
        ld	bc, 0x7F8A		; enable upper and lower rom
        out (c),c
        
        ; NMI is set back to open drain
        ; and RAMDIS signal set to back to input signal (no driving)
        
        ; disable ram dis
        
        ld	bc,DATAPORT					; data out port
        out (c),c
        ld	a, 0x1A		;
        out	(c),a						; command lo
        ld	a, 0x43			;
        out	(c),a						; command	hi
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ld	bc, 0x7F8A		; enable lower rom and disable upper
        out (c),c
        ; setup CRTC (to ensure interrupt is generated)
        ld  sp,0xFFFC
        ; mute sound
        ld	hl,ui_psg_regs+15
        ld	a,15
psg_loop:
        ld	bc,0xF4C0
        out	(c),a
        ld	b, 0xF6
        out (c),c
        out (c),0
        dec	b
        outd
        ld	bc,0xF680
        out (c),c
        out (c),0
        dec	a
        jp	p,psg_loop
        
        ld	hl,ui_crtc_regs+16
        call setup_crtc

        ld	hl,cpu_regs
        
        ; copy regs to ROM
        
        ld	bc,DATAPORT					; data out port
        out (c),c
        ld	a, C_ROMWRITE & 0xFF		;
        out	(c),a						; command lo
        ld	a, C_ROMWRITE>>8			;
        out	(c),a						; command	hi
        out	(c),l						; rom dest addr
        out	(c),h						; rom dest addr => snamem
        ld	a,29
        out	(c),a						; size
        xor	a
        out	(c),a						; size 29
        ld a,255
        out	(c),a						; 1 bank (0 = M4 ROM, 255 = nmi rom)
        
        ; copy af,bc,de,hl to snamem+0x11
        
        ld	a,8
        ld	hl, 0xFFF4
cp_regs4:
        inc	b
        outi
        dec	a
        jr	nz,cp_regs4
        
        ld	a, (0xFFF3)		; r
        out (c),a
        ld	a,(0xFFF1)		; i
        out (c),a
        ld	a,(0xFFF2)		; get flags (PF flag)
        srl a
        srl a
        and 1
        
        out (c),a			; IFF0
        out (c),a			; IFF1
        db 0xDD,0x5D			; ld e, IXl
        db 0xDD,0x54			; ld d, IXh
        out (c),e			; IXl
        out (c),d			; IXh
        db 0xFD,0x5D			; ld e, IXl
        db 0xFD,0x54			; ld d, IXh
        
        out (c),e			; IYl
        out (c),d			; IYh
        ld hl,(0xFFFE)
        ld de,2
        add hl,de			; skip PC on stack (not using retn)
        out (c),l
        out (c),h
        xor a
        ld	hl,get_pc_stack
        ld	de,0xFFF0
        ld	bc,12
        ldir
        ld	hl,(0xFFFE)
        ld	bc,0x7F8C
        jp	0xFFF0			; read PC from stack with both roms disabled.
ret_pc:
        ld	bc,DATAPORT
        out (c),e			; PCl
        out (c),d			; PCh
        
        ld  sp,0xFFFE
        ld	a,im2_jumptable>>8
        ld	i,a
        xor a
        ;ld hl,detect
        ;push hl
        ;retn
detect:
        ei
        halt
        di
        ; a should now return 1 for IM 1 and 2 for IM2
        
        out (c),a
    
    
        ; save alternate reg set
        ex af,af'
        push af				; 0x..
        ex af,af'
        pop	hl
        out (c),l			; AF´l
        out (c),h			; AF´h
        exx
        push bc
        exx
        pop	hl
        out (c),l			; BC´l
        out (c),h			; BC´h
        exx
        ld	bc,DATAPORT	
        out (c),e			; DE´l
        out (c),d			; DE´h
        out (c),l			; HL´l
        out (c),h			; HL´h
        exx
        ld	bc,ACKPORT
        out (c),c						; write it to M4 rom
    
            
        ld	bc, 0x7F8A		; enable upper and lower rom
        out (c),c
    

    
        ; -- put code here
        ld sp,0xFFFC
        
        ;jr	back		 	; temp skip write mem
        
        jp write_base_ram
        
back_write_base_ram:
        ld	sp,0xC000
        ld	bc, 0x7F82		; enable upper and lower rom, screen mode 2
        out (c),c

        ld a,(memdump_sz)
        cp 0
        jr nz,no_detect
        ; detect if 64KB or 128KB ram
        
        ld bc,0x7FC0
        out (c),c
        
        ld a,(0x6000)
        xor 0xF5
        ld (0x6000),a
        ld e,a
        ld a,(0x6001)
        xor 0xA3
        ld (0x6001),a
        ld d,a
        ; select bank 4
        ld bc,0x7FC7
        out (c),c
        ld c,0x40			; 64KB
        ld a,(0x6000)
        cp e
        jr z,not_128
        ld a,(0x6001)
        cp d
        jr z,not_128
        ld c,0x80			; 128KB
not_128:
        ld e,c
        ld bc,0x7FC0
        out (c),c
        
        
        call set_dump_size
no_detect:
            
        call write_jumper
        
        ld	bc, 0x7F8A		; disable upper and enable lower rom, screen mode 2
        out (c),c
    
        ; ui handling
        
        call interface
        
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
    
        ld	sp,0
        jp read_base_ram
ret_read_base_ram:
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	a,(sna_header+0x25)
        cp	0
        jr	nz, not_im0
        im	0
not_im0:cp	1
        jr	nz, not_im1
        im	1
not_im1:cp	2
        jr	nz, not_im2
        im	2
not_im2:			
        ; store "sna jumper" copy in RAM aswell
        ld	hl,0xFFF0
        ld	d,h
        ld	e,l
        ld	bc, 16
        ldir
    

        ld	bc, 0x7F8A		; disable upper and enable lower rom, screen mode 2
        out (c),c
        ;jp skipset
        ; Setup pen colors 0 to 15 and border color
        ld	hl,sna_header+0x2F+16
        ld	bc,0x7F10
SNA_SetupGA:	
        out (c),c
        ld	a,(hl)
        dec	hl
        set	6,a
        out	(c),a
        dec	c
        jp	p,SNA_SetupGA
        
        ; Select last active pen
        ld	a,(hl)
        out	(c),a  



        ; CRTC setup
        ld	hl,sna_header+0x43+17
        ld	bc,0xBD00+17
SNA_SetupCRTC:
        dec	b
        out	(c),c
        ld	b,0xBE
        outd
        dec	c
        jp	p,SNA_SetupCRTC
        ; Select active CRTC register
        ; HL = Offset &42
        ; B  = &BD
        outd
            
        ; ram config
                
        ld	a,(sna_header+0x41)
        or	0xC0
        ld	bc,0x7f00
        out	(c),a
    
        ; Setup AY3 registers

        ld	hl,sna_header+0x5B+15
        ld	a,15
SNA_SetupAY3:
        ld	bc,0xF4C0
        out	(c),a
        ld	b, 0xF6
        out (c),c
        out (c),0
        dec	b
        outd
        ld	bc,0xF680
        out (c),c
        out (c),0
        dec	a
        jp	p,SNA_SetupAY3
        ; Select last active AY3 register
        ld	bc,0xF5C0
        outd
        ld	b,0xF6
        out	(c),c
        out (c),0
            

        ; will disable nmi rom in "next" rmr write
        
        ld	bc,DATAPORT
        xor	a
        out	(c),a			; ignore first byte
        ld	a,C_NMIOFF&0xFF	
        out	(c),a
        ld	a,C_NMIOFF>>8	
        out	(c),a
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ; pop registers
            
        exx
        ex	af, af'		; '
        ld	sp,sna_header+0x26
        pop	af
        pop	bc
        pop	de
        pop	hl
        ex	af, af'		; '
        exx
        ld	sp,sna_header+0x15
        pop	de
        pop	hl
        ld	a,(sna_header+0x1A)	
        ld	i,a
        
        ld	sp,sna_header+0x1d
        pop	ix
        pop	iy

        
        ld a,(ga_multi)
        or 0x80
        ld c,a
        ld b,0x7F
        ld sp,cpu_regs	; sna_header+0x11
        pop af
        ld sp,(sna_header+0x21)
        
        jp 0xFFF0

        ; exit back
        ; write jump back routine to upper rom
        ; only use reg a and bc
write_jumper:		
        ld	bc,DATAPORT					; data out port
        out (c),c
        ld	a, C_ROMWRITE & 0xFF		;
        out	(c),a						; command lo
        ld	a, C_ROMWRITE>>8			;
        out	(c),a						; command	hi
        ld	a,0xF0
        out	(c),a						; rom dest addr
        ld	a,0xFF
        out	(c),a						; rom dest addr 0xFFF0
        ld	a,14
        out	(c),a						; size
        xor	a
        out	(c),a						; size 12
        out	(c),a						; 0 bank (0 = M4 ROM) 
        ; code
        ld	a,0xED
        out	(c),a						; 1
        ld	a,0x49
        out	(c),a						; 2 ED 49 out (c),c
        ld	a,0x01
        out	(c),a						; 3 ld bc,0xDFxx
        ld a,(romsel)
        out	(c),a						; 4 xx
        ld	a,0xDF
        out	(c),a						; 5 DF
        ld	a,0xED
        out	(c),a						; 6
        ld	a,0x49
        out	(c),a						; 7 ED 49 out (c),c
        ld	a,0x01						; 
        out	(c),a						; 8 ld bc,xxxx
        ld hl,(cpu_regs+2)
        out	(c),l						; 9
        out	(c),h						; 10
        
        ld	l, 0xFB			; ei
        ld	a,(sna_header+0x1B)
        and	1
        jr	nz,int_en
        ld	l,0xF3			; di
        
int_en:		
        out	(c),l						; 11
        ld a,0xC3
        out	(c),a						; 12 JP
        ld hl,(sna_header+0x23)			; 
        out	(c),l						; 13 PCl
        out	(c),h						; 14 PCh

        ld	b,ACKPORT>>8			    ; kick command
        out	(c),c
        ret		
        ; hl = src filename
        ; copy sna file into tmp1.bin
load_sna:		
        
        ld a,(m4romnum)
        ld	bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        
        ;
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_COPYFILE2&0xFF	
        out	(c),a
        ld	a,C_COPYFILE2>>8	
        out	(c),a
        
        ; output dest filename

        ld de, temp_fn
lsrc_fn:
        ld a,(de)
        inc de
        out (c),a
        or a
        jr nz, lsrc_fn
        
        ; output src filename
        ld e,l
        ld d,h
ldest_fn:
        ld a,(de)
        inc de
        out (c),a
        or a
        jr nz, ldest_fn
                
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ld a,(iy+3)			; get response
        or a
        ret nz
        ; read sna header
        
        ld	hl,cmd_open2
        ld	bc,DATAPORT
        ld	a,17
rsendloop2:
        inc	b
        outi
        dec	a
        jr	nz, rsendloop2
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ld	e,(iy+3)		; get fd
    
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_READ2&0xFF	
        out	(c),a
        ld	a,C_READ2>>8
        out	(c),a			
        out	(c),e			; fd		
        xor a
        out	(c),a			; size 00
        ld a,1
        out	(c),a			; size 0x0100
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        push de
        ; overwrite current sna header
        
        ld	bc,DATAPORT					; data out port
        out (c),c
        ld	a, C_ROMWRITE & 0xFF		;
        out	(c),a						; command lo
        ld	a, C_ROMWRITE>>8			;
        out	(c),a						; command	hi
        xor a
        out	(c),a						; rom dest addr
        ld a,0x1						; 
        out	(c),a						; offset 0x100
        ld	a,0xFF
        out	(c),a						; size
        xor a
        out	(c),a						; size 00E0
        
        ld a,255
        out	(c),a						; 1 bank (0 = M4 ROM, 255 = nmi rom)
        
        ld hl,(0xFF02)
        ld de,8
        add	hl,de						; point to response data
        ld d,0xFF
wrtsnahead:
        ld a,(hl)
        out (c),a						; write memdump size
        inc hl
        dec d
        jr nz,wrtsnahead
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        call write_jumper
        pop de	; restore fd
        
        ; load banks, if needed
        
        ld a,(memdump_sz)
        cp 0x40
        jr z,no_add_banks

        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_SEEK&0xFF	
        out	(c),a
        ld	a,C_SEEK>>8	
        out	(c),a
        out	(c),e			; fd
        xor a
        out	(c),a
        ld a,1
        out	(c),a			; size 0x0100
        ld a,1
        out	(c),a
        xor a
        out	(c),a			; size 0x00010100

        ld	b,ACKPORT>>8	; kick command
        out	(c),c

        
        ld bc,0x7FC4
banks_loop:
        out (c),c			; select bank
        push bc
        exx
        ld	de,0x4000
        exx
        ld	d,8				; 8 * 2048 = 16384
readbnkloop:		
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_READ2&0xFF	
        out	(c),a
        ld	a,C_READ2>>8	
        out	(c),a			
        out	(c),e			; fd		
        xor a
        out	(c),a			; size 00
        ld a,8
        out	(c),a			; size 0x0800
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        exx
        ld	hl,(0xFF02)		; copy to ram
        ld	bc,8
        add	hl,bc
                            ; de increases from 0
        ld	bc,0x800
        ldir
        exx
        
        dec	d
        jr	nz, readbnkloop
        pop bc
        inc c				; next bank
        ld a,0xC8
        cp c
        jr nz,banks_loop
        ld bc,0x7FC0
        out (c),c
no_add_banks:		
        ; close the file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        xor a
        ret
write_sna:
        
        ld a,(m4romnum)
        ld	bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        
        ;
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_COPYFILE2&0xFF	
        out	(c),a
        ld	a,C_COPYFILE2>>8	
        out	(c),a

        ; output dest filename
        ld e,l
        ld d,h
dest_fn:
        ld a,(de)
        inc de
        out (c),a
        or a
        jr nz, dest_fn


        ; output src filename

        ld de, temp_fn
src_fn:
        ld a,(de)
        inc de
        out (c),a
        or a
        jr nz, src_fn
                
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ld a,(iy+3)			; get response
        cp 0
        ret nz

        ; open dest file

        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_OPEN&0xFF	
        out	(c),a
        ld	a,C_OPEN>>8	
        out	(c),a
        ld a,FA_READ | FA_WRITE | FA_REALMODE
        out	(c),a
    
        ; filename still in HL
new_fn:
        ld a,(hl)
        inc hl
        out (c),a
        or a
        jr nz, new_fn
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c

        ; now overwrite sna header, with valid one
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_WRITE2&0xFF	
        out	(c),a
        ld	a,C_WRITE2>>8	
        out	(c),a			
        ld e,(iy+3)			; get fd
        out	(c),e			; fd
        xor a
        out	(c),a			; size 00
        ld a,0x1
        out	(c),a			; size 0x0100
        ld hl,sna_header
        ld a,255
sendhead2:
        inc	b
        outi
        dec a
        jr	nz, sendhead2
        inc	b
        outi
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        
        ; check if 128KB
        ld a,(memdump_sz)
        cp 0x40
        jr z,is_only64KB
        
        ; otherwise write extended banks also
            
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_SEEK&0xFF	
        out	(c),a
        ld	a,C_SEEK>>8	
        out	(c),a
        out	(c),e			; fd
        xor a
        out	(c),a
        ld a,1
        out	(c),a			; size 0x0100
        out	(c),a			; size 0x010100
        xor a
        out	(c),a			; size 0x00010100

        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ; write banks
        
        exx
        ld bc,0x7FC4
        ld e,4
        
        
bankloop:
        
        out (c),c
        exx
        
        ld	d,16			; 16 * 1024 = 16384
        ld	hl,0x4000
writebank:		
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_WRITE2&0xFF	
        out	(c),a
        ld	a,C_WRITE2>>8	
        out	(c),a			
        out	(c),e			; fd
        db 0xDD,0x6B			; ld IXl, e
        db 0xDD,0x62			; ld IXh, d
        
        ld de,0x400
        out	(c),e			; size 00
        out	(c),d			; size 0x0400
        xor a
sendbank:
        inc	b				; 1
        outi				; 2
        dec	de				; 1
        cp	e				; 1
        jr	nz,sendbank	; 2
        cp	d				; 1
        jr	nz, sendbank	; 2 = 10
        
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        db 0xDD,0x5D			; ld e, IXl
        db 0xDD,0x54			; ld d, IXh
        
        dec	d
        jr	nz, writebank
        exx
        
        inc c			; C4, C5..
        dec e
        jr nz,bankloop
        exx
        
        
is_only64KB:
        ; close the file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ; done
        xor a
        ret
        
read_base_ram:
        
        ; open file for read
        
        ld	hl,cmd_open2
        ld	bc,DATAPORT
        ld	a,17
rsendloop1:
        inc	b
        outi
        dec	a
        jr	nz, rsendloop1
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ld bc,0x7FC0
        out (c),c
        ld a,(m4romnum)
        ld bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        ld	e,(iy+3)		; get fd
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_SEEK&0xFF	
        out	(c),a
        ld	a,C_SEEK>>8	
        out	(c),a
        out	(c),e			; fd
        xor a
        out	(c),a
        ld a,1
        out	(c),a			; size 0x0100
        xor a
        out	(c),a
        out	(c),a			; size 0x00000100

        ld	b,ACKPORT>>8	; kick command
        out	(c),c


        exx
        ld	de,0
        exx
        ld	d,32			; 64 * 1024 = 65536
readloop:		
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_READ2&0xFF	
        out	(c),a
        ld	a,C_READ2>>8	
        out	(c),a			
        out	(c),e			; fd		
        xor a
        out	(c),a			; size 00
        ld a,8
        out	(c),a			; size 0x0800
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        exx
        ld	hl,(0xFF02)		; copy to ram
        ld	bc,8
        add	hl,bc
                            ; de increases from 0
        ld	bc,0x800
        ldir
        exx
        
        dec	d
        jr	nz, readloop
        
        ; close the file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        jp 	ret_read_base_ram
        
write_base_ram:
        ; open file for write
        
        ld	hl,cmd_open
        ld	bc,DATAPORT
        ld	a,17
sendloop1:
        inc	b
        outi
        dec	a
        jr	nz, sendloop1
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ld a,(m4romnum)
        ld	bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        ld	e,(iy+3)		; get fd
    
        ld bc,0x7FC0
        out (c),c
        
        ; save 'sna header', to be modified later

        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_WRITE2&0xFF	
        out	(c),a
        ld	a,C_WRITE2>>8	
        out	(c),a			
        
        out	(c),e			; fd
        xor a
        out	(c),a			; size 00
        ld a,0x1
        out	(c),a			; size 0x0100
        ld hl,sna_header
        ld a,255
sendhead:
        inc	b
        outi
        dec a
        jr	nz, sendhead
        inc	b
        outi
        
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c

        ;ld	e,(iy+3)		; get fd
        ;ld e,a				; fd
        ld  ix,(0xFF10)		; get mem write from M4 rom
        
        ; save first 16KB (overlapped by NMI rom)
        ld	iy,upper_rom_ret
        ld	hl,0			; start address 0
        ld	d,16			; 16 *1024 = 16384
        jp  (ix)
upper_rom_ret:
        
        ;pop de
        db 0xDD,0x5D			; ld e, IXl
        
        
        ld	bc, 0x7F8A		; disable upper rom
        out (c),c
        
        ; save remaing 48KB in 1024 byte chunks

    
        ld	d,48			; 48 * 1024 = 49152
writeloop:		
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_WRITE2&0xFF	
        out	(c),a
        ld	a,C_WRITE2>>8	
        out	(c),a			
        out	(c),e			; fd
        db 0xDD,0x6B			; ld IXl, e
        db 0xDD,0x62			; ld IXh, d
        
        ld de,0x400
        out	(c),e			; size 00
        out	(c),d			; size 0x0400
        xor a
sendloop2:
        inc	b				; 1
        outi				; 2
        dec	de				; 1
        cp	e				; 1
        jr	nz,sendloop2	; 2
        cp	d				; 1
        jr	nz, sendloop2	; 2 = 10
        
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        db 0xDD,0x5D			; ld e, IXl
        db 0xDD,0x54			; ld d, IXh
        
        dec	d
        jr	nz, writeloop
        
        
        ; close the file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        jp	back_write_base_ram


            
get_pc_stack:
        out (c),c			; 2		disable upper and lower rom
        ld e,(hl)			; 1
        inc hl				; 1
        ld d,(hl)			; 1
        ld c,0x8A			; 2 disable upper, enable lower
        out (c),c			; 2
        jp ret_pc			; 3  = 12 bytes

interface:
        ld a,0x54
        ld	bc,0x7F10
        out (c),c
        out (c),a
        ld	bc,0x7F00
        out (c),c
        out (c),a
        ld a,0x4B		; white
        inc c
        out (c),c
        out (c),a

        ; clear screen
        xor a
        ld hl,0xC000
        ld (hl),a
        ld de,0xC001
        ld bc,0x3FEF
        ldir

        ld	hl,0 ; 10*8*2
        ld (keyb_layout_offset),hl
        
        ld	hl,txt_title
        ld	de,L_MAINTITLE
        call disp_text
        
        ; Display all z80 registers		
        ld hl,txt_z80regs
        ld de,L_Z80_REGSTITLE
        call disp_text

        ld ix,temp_buf			; use some temp ram area

        ld hl,txt_regs1
        ld de,(L_Z80_REGS_X<<8)|L_Z80_REGS_Y+2
        ld iy,cpu_regs
        ld b,4
        call disp_regs			; display AF, BC, DE, HL
        
        ld de,(L_Z80_REGS_X<<8)|L_Z80_REGS_Y+6
        ld iy,sna_header+0x21	; point to SP
        ld b,2
        call disp_regs			; display SP, PC
        
        ld de,(L_Z80_REGS_X+11<<8)|L_Z80_REGS_Y+2
        ld b,4
        inc iy					; point to alt AF....
        call disp_regs			; display alt AF, BC, DE, HL
        
        ld de,(L_Z80_REGS_X+11<<8)|L_Z80_REGS_Y+6
        ld iy,sna_header+0x1D	; point to IX
        ld b,2
        call disp_regs			; display IX,IY
        
        ; display 8 bit regs R, I		
        ld	hl,txt_r
        ld de,(L_Z80_REGS_X<<8)|L_Z80_REGS_Y+8
        call disp_text
        ld a,(sna_header+0x19)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld (ix+2),0
        ld	hl,temp_buf
        ld de,(L_Z80_REGS_X+7<<8)|L_Z80_REGS_Y+8
        call disp_text
        
        ld	hl,txt_i
        ld de,(L_Z80_REGS_X+11<<8)|L_Z80_REGS_Y+8
        call disp_text
        ld a,(sna_header+0x1A)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_Z80_REGS_X+18<<8)|L_Z80_REGS_Y+8
        call disp_text
        
        ; Display interrupt mode		
        ld	hl,txt_im
        ld de,(L_Z80_REGS_X<<8)|L_Z80_REGS_Y+9
        call disp_text
        ld a,(sna_header+0x25)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_Z80_REGS_X+7<<8)|L_Z80_REGS_Y+9
        call disp_text
        
        ld	hl,txt_ints
        ld de,(L_Z80_REGS_X+11<<8)|L_Z80_REGS_Y+9
        call disp_text
        ld a,(sna_header+0x1B)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_Z80_REGS_X+18<<8)|L_Z80_REGS_Y+9
        call disp_text

        ; Display header columns 0 - 0x10
        ld de,L_HW_REGSHEADER
        ld	hl,temp_buf
        ld b,0x11
        xor a
columns:
        push af
        push bc
        push de
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        pop de
    
        push hl
        push de
        
        call disp_text
        pop de
        pop hl
        pop bc
        pop af
        inc a
        inc d
        inc d
        inc d
        djnz columns
        
        ; display Palette, PSG, CRTC		
        ld hl,txt_pal
        ld de,L_HW_REGS
        call disp_text
        inc hl
        ld de,L_HW_REGS+1
        call disp_text
        inc hl
        ld de,L_HW_REGS+2
        call disp_text
        
        ; Display palette		
        ld hl,temp_buf
        
        ld de,L_HW_REGSHEADER+2
        ld b,0x11
        ld a,(ga_pen)
        ld iy,palette
        call disp_columns
        
        ld de,L_HW_REGSHEADER+3
        ld b,0x10
        ld a,(psg_sel)
        ld iy,psg_regs
        call disp_columns
        
        ld de,L_HW_REGSHEADER+4
        ld b,0x10
        ld a,(crtc_sel)
        ld iy,crtc_regs
        call disp_columns
        
        ; display RMR, MMR, ROM (sel)
        ld hl,txt_rmr
        ld de,(L_HW_RMR_MMR_ROM_X<<8)|L_HW_RMR_MMR_ROM_Y
        call disp_text
        inc hl
        ld de,(L_HW_RMR_MMR_ROM_X<<8)|L_HW_RMR_MMR_ROM_Y+1
        call disp_text
        inc hl
        ld de,(L_HW_RMR_MMR_ROM_X<<8)|L_HW_RMR_MMR_ROM_Y+2
        call disp_text
        
        ; disp values
        ld a,(ga_multi)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_HW_RMR_MMR_ROM_X+7<<8)|L_HW_RMR_MMR_ROM_Y
        call disp_text
        
        ld a,(ramconf)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_HW_RMR_MMR_ROM_X+7<<8)|L_HW_RMR_MMR_ROM_Y+1
        call disp_text
        
        ld a,(romsel)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_HW_RMR_MMR_ROM_X+7<<8)|L_HW_RMR_MMR_ROM_Y+2
        call disp_text
        
        ; Display PPIA,B,C, PPICTRL
        ld hl,txt_ppi
        ld de,(L_HW_PPI_X<<8)|L_HW_PPI_Y
        call disp_text
        inc hl
        ld de,(L_HW_PPI_X<<8)|L_HW_PPI_Y+1
        call disp_text
        inc hl
        ld de,(L_HW_PPI_X<<8)|L_HW_PPI_Y+2
        call disp_text
        inc hl
        ld de,(L_HW_PPI_X<<8)|L_HW_PPI_Y+3
        call disp_text
        
        ; disp PPI values
        ld a,(ppiA)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld	hl,temp_buf
        ld de,(L_HW_PPI_X+7<<8)|L_HW_PPI_Y
        call disp_text
        
        ld a,(ppiB)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld hl,temp_buf
        ld de,(L_HW_PPI_X+7<<8)|L_HW_PPI_Y+1
        call disp_text
        
        ld a,(ppiC)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld hl,temp_buf
        ld de,(L_HW_PPI_X+7<<8)|L_HW_PPI_Y+2
        call disp_text
        
        ld a,(ppiCtrl)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld hl,temp_buf
        ld de,(L_HW_PPI_X+7<<8)|L_HW_PPI_Y+3
        call disp_text
        
        ld a,(memdump_sz)
        cp 0x40
        jr	nz, not64sz
        ld	hl,txt_64KB
        jr	dumpsz_set
not64sz:
        ld	hl,txt_128KB
dumpsz_set:
        ld de,L_DUMPSIZE
        call disp_text		
        ld a,(keyb_layout)
        cp 37				; french
        jr	z, not_qwerty
        ld	hl,txt_qwerty
        jr	keyb_set
not_qwerty:
        ld	hl,240			; 10*8*3
        ld (keyb_layout_offset),hl
        ld	hl,txt_azerty
keyb_set:
        ld de,L_KEYBOARDTYPE        
        call disp_text
        
        ; draw menu items
        ld b,6
        ld hl,txt_menu
        ld de,L_MENU
menuloop:
        push bc
        push de
        call disp_text
        pop de
        pop bc
        inc hl
        inc e
        djnz menuloop
        
        
        ; ppi reset ports
        ;ld bc,0xF780
        ;out (c),c
        
        xor a
        ld (ypos),a
        ld (anim_count),a
        ld (cur_toggle),a
        ld (cur_flash),a
        ld (frame_count),a
        ld (last_char),a
        ld (inum),a
        ld (delay_char),a
        ld hl,0
        ld (last_scr_y),hl
        ld (scr_pos_input),hl
        ld de,0xC000 + 15*80 + 30
        ld (last_scr_y),de

        ; make sure space or fire is not already pressed		
release_space:		
        call keyscan
        ld a,(keymap+5)
        and 0x80		; is it space
        ;jr	z,release_space		
        
        ld hl,0
        call display_memory
mainloop:

        ld b,0xf5
vsync:	in a,(c)
        rra
        jp nc, vsync
        
        ld bc,0x7F10
        ld a,0x54
        out (c),c
        out (c),a
        
        call keyscan
        ld bc,0x7F10
        ld a,0x54
        out (c),c
        out (c),a
        
        ld a,(frame_count)
        inc a
        ld (frame_count),a
        cp	15
        jp nz, skip_frame
        
        ; only update every so often
        xor a
        ld (frame_count),a
        
        ; return 1 to 6 for each menu entry, 0 if no menu key pressed
        call check_menu_keys
        or a
        jr z,up_down
        dec a
        ld (ypos),a
        call clear_pointer
        jp z,save_snap
        dec a
        jp z,load_snap
        dec a
        jp z,change_dumpsz
        dec a
        jp z,pokes
        dec a
        jp z,dispmem
        ret

        ; check if UP/DOWN is pressed
up_down:
        ld a,(keymap+9)
        and 2		; joy down
        jr z,is_down
        ld a,(keymap+0)
        and 4		; cur down
        jr nz,not_down
is_down:		
        ld a,(ypos)
        inc a
        cp 6			; check if exceed menu
        jr nz,press_registered
        xor a			; set to first item
        jr press_registered
not_down:
        ld a,(keymap+9)
        and 1			; joy up
        jr z,is_up
        ld a,(keymap+0)
        and 1			; cur up
        jr nz, not_up
is_up:
        ld a,(ypos)
        cp 0
        jr nz, not_top_item
        ld a,5			; set to last item
        jr press_registered
not_top_item:
        dec a
        jr press_registered

not_up:		
        call draw_pointer
        jr skip_frame

press_registered:
        ld (ypos),a		
        call clear_pointer
        call draw_pointer
        
skip_frame:
        ; check if FIRE or SPACE or RETURN is pressed
        ld a,(keymap+9)
        and 0x40		; joy fire 2
        jr z,is_fire
        ld a,(keymap+2)
        and 4			; return
        jr z,is_fire
        ld a,(keymap+5)
        and 128			; space
        jp nz,not_fire
        
is_fire:	
        ld a,(ypos)
        cp #0
        jr nz, not_save_snap
save_snap:
        call clear_lines
        ld hl,txt_filename
        ld de,L_SAVESNAPSHOT
        call disp_text
        ld iy,key_translate
        ld ix,I_SAVESNAPSHOT
        call get_input
        cp 0
        jp z,not_fire		; esc was pressed == cancel
        ld hl,txt_save
        ld de,L_SAVING
        call disp_text
        ;
        ld hl,sna_fn
        ld de,(8<<8)| 24
        call disp_text
        
        ld hl,sna_fn
        call write_sna
        cp 0
        jr nz,not_success
        ld hl,txt_success
        jr save_done
not_success:
        ld hl,txt_failed
save_done:
        ld a,(inum)		; filename len
        add 9
        ld d,a
        ld e,24
        call disp_text
        
        ; wait for enter,return,esc
        
        call wait_return
        call clear_lines
        
        jp not_fire
        
not_save_snap:
        cp #1
        jr nz, not_load_snap
load_snap:
        call clear_lines
        ld hl,txt_filename
        ld de,L_LOADSNAPSHOT
        call disp_text
        ld iy,key_translate
        ld ix,I_LOADSNAPSHOT
        call get_input
        cp 0
        jp z,not_fire		; esc was pressed == cancel
        ld hl,txt_load
        ld de,L_LOADING
        call disp_text
        ;
        ld hl,sna_fn
        ld de,(9<<8)| 24
        call disp_text
        
        ld hl,sna_fn
        call load_sna
        cp 0
        jr nz,not_success1
        ld hl,txt_success
        jr load_done
not_success1:
        ld hl,txt_failed
load_done:
        ld a,(inum)		; filename len
        add 10
        ld d,a
        ld e,24
        call disp_text
        
        ; wait for enter,return,esc
        
        call wait_return
        call clear_lines
        ld bc,0x7F8A
        out (c),c
        jp interface
        
not_load_snap:
        cp #2
        jr nz, not_change_dumpsz
        
change_dumpsz:
        ld a,(memdump_sz)
        cp 0x40
        jr nz, not_set_64
        ld e,128
        ld	hl,txt_128KB
        jr dump_size_set
not_set_64:
        ld e,64
        ld	hl,txt_64KB
dump_size_set:
        call set_dump_size		
        ld de,L_DUMPSIZE
        call disp_text
        call wait_return_released
        jp not_fire
        
not_change_dumpsz:
        cp #3
        jp nz, not_pokes
        call clear_lines
        
pokes:	ld ix,temp_buf2
        xor a
        ld (poke_count),a
poke_loop:
        
        ld hl,txt_address
        ld de,L_POKEADDRESS
        call disp_text
        push ix
        ld iy,key_poke_translate
        ld ix,I_POKEADDRESS
        call get_input
        pop ix
        cp 0
        jp z,poke_done
        
        ld a,(inum)
        cp 0
        jr z,poke_loop
        ld hl,sna_fn+1
        call ascii2bin
        
        call display_memory

        ld (ix),l
        ld (ix+1),h
        
        ld hl,txt_val
        ld de,L_POKEVAL
        call disp_text
val_loop:
        push ix
        ld iy,key_poke_translate
        ld ix,I_POKEVAL
        call get_input
        pop ix
        cp 0
        jr z,poke_done
        ld a,(inum)
        cp 0
        jr z,val_loop
        ld hl,sna_fn+1
        call ascii2bin
        ld (ix+2),l
        
        ld iy,temp_buf
        ld a,(ix+1)
        call conv_hex
        ld (iy+0),'['
        ld (iy+1),d
        ld (iy+2),e
        ld a,(ix)
        call conv_hex
        ld (iy+3),d
        ld (iy+4),e
        ld (iy+5),']'
        ld (iy+6),'='
        ld a,(ix+2)
        call conv_hex
        ld (iy+7),d
        ld (iy+8),e
        ld (iy+9),0
        
        ld	hl,temp_buf
        ld de,L_POKEAPPLIED
        call disp_text
        
        
        inc ix
        inc ix
        inc ix
        ld a,(poke_count)
        inc a
        ld (poke_count),a
        
        jp poke_loop
poke_done:
        ld a,(poke_count)
        cp 0
        jp z, not_fire
        ld ix,temp_buf2
        call apply_pokes
        ld bc,0x7F8A
        out (c),c
        
        ld hl,txt_applied
        ld de,L_POKEAPPLIED
        call disp_text
        call wait_return
        call clear_lines
        jr not_fire

not_pokes:
        cp #4			; disp mem
        jr nz, not_dispmem
dispmem:
        call display_memory_input
        jr not_fire
not_dispmem:		
        cp #5
        jr z, exit_menu
        
not_fire:
        jp mainloop

exit_menu:				
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        ; wait for return/enter/space key to be pressed and de-pressed
wait_return:
wait_save_key_press:
        call keyscan
        ld a,(keymap+2)
        and 0x4		; return
        jr z,save_key_pressed
        ld a,(keymap+5) ; space
        and 128
        jr z,save_key_pressed
        ld a,(keymap)
        and 0x40		; enter
        jr nz,wait_save_key_press
wait_return_released:
save_key_pressed:
        call keyscan
        ld a,(keymap+2)
        and 0x4		; return
        jr z,save_key_pressed
        ld a,(keymap+5) ; space
        and 128
        jr z,save_key_pressed
        ld a,(keymap)
        and 0x40		; enter
        jr z,save_key_pressed
        ret
wait_esc_rel:
rel_esc:
        call keyscan
        
        ld a,(keymap+8)
        and 0x4		; esc
        jr z,rel_esc
        
        ret
        ; get input entry for filename
        
        ; iy = keymap
        ; ixl = max len
        ; ixh = x pos
get_input:
        ; check if FIRE and SPACE and RETURN are released
        call keyscan
        
        ld a,(keymap+9)
        and 0x20		; joy fire 2
        jr z,get_input
        ld a,(keymap+2)
        and 4			; return
        jr z,get_input
        ld a,(keymap+5)
        and 128			; space
        jr z,get_input
        ; init memory vars
        
        ld hl,0xC000 + 23*80 ;+ 16
        ld c,ixh
        ld b,0
        add hl,bc
        
        ld (scr_pos_input),hl
        xor a
        ld (frame_count),a
        ld (cur_flash),a
        ld (inum),a
        ld a,20
        ld (delay_char),a
        ld hl,sna_fn
        ld a,'/'
        ld (hl),a
        

input_loop:

        ld b,0xf5
vsync2:	in a,(c)
        rra
        jp nc, vsync2
        call keyscan
        
        ld a,(cur_flash)
        inc a
        cp 25
        jr nz, no_toggle
        ld a,(cur_toggle)
        xor 1
        ld (cur_toggle),a
        
        xor a
no_toggle:
        ld (cur_flash),a
        
        ld a,(cur_toggle)
        cp 0
        jr z, cur_blank
        ld a,' '
        jr disp_cur
cur_blank:
        ld a,'_'
disp_cur:
        ld de,(scr_pos_input)
        ld c,0
        call write_char
            
    ;	ld a,(frame_count)
    ;	inc a
    ;	ld (frame_count),a
    ;	cp 5
    ;	jp nz, skip_key_checking
    ;	xor a
    ;	ld (frame_count),a
    
        
        
        ; check if key is pressed

        push iy	; retrieve key map
        pop bc
        ;ld bc,key_translate
        ld hl,(keyb_layout_offset)
        add	hl,bc
        ld bc,0
        ld a,(keymap+2)
        and 0x20
        jr z, is_shift
        ld a,(keymap+8)
        and 0x40
        jr nz, not_shift		; not caps_lock either
        ; mask out caps-lock & shift
        ld a,(keymap+8)
        or 0x40
        ld (keymap+8),a
        
is_shift:
        ld a,(keymap+2)
        or 0x20
        ld (keymap+2),a
        ;ld hl,key_translate_shift
        ld bc,10*8
not_shift:
        
        add hl,bc
        ld b,10
        ld de,keymap
    
key_pressed:
        push de
        push bc
        ld a,(de)	; keymap
        cp 0xFF
        jr z,next_key_row	; no keys pressed in this row
        
        ld b,0
        bit 0,a
        jr z,key_bit_clear
        ld b,7
        
bitloop:
        sla a		; carry = a<<1
        jr nc, key_bit_clear
        
        djnz bitloop
        jr next_key_row
        
key_bit_clear:
        
        ld a,7
        sub b		; 8 - bit set
        ld d,0
        ld e,a
        push hl
        add hl,de	; key_translate + (bit set)
        ld a,(hl)
        pop hl

        cp 0
        jr z, next_key_row	; no valid key pressed
        pop de
        pop bc
        ld c,a
        ld a,(last_char)
        ld b,a
        ld a,c
        cp b
        jr nz,char_found		; not same as last time, so no penality
        ; it is same char
        ld a,(delay_char)
        cp 0
        ld a,c
        jr z, char_found		; delay is done
        jp no_valid_char		; skip char, repeat is too fast
next_key_row:
        ld bc,8
        add hl,bc ; next translation row
        pop bc
        pop de
        inc de		; next key row
    
        djnz key_pressed
        xor a
char_found:

        cp 0
        jp z, no_valid_char
        
        ld (last_char),a
        ; print char
        
        cp 8
        jr nz, not_del
        ld a,(inum)			; are we at first char?
        cp 0
        jp z,skip_key_checking
        dec a
        ld (inum),a
        ld hl,sna_fn+1
        ld e,a
        ld d,0
        add hl,de
        ld (hl),d
        ld de,(scr_pos_input)
        ld a,' '
        push de
        ld c,0
        call write_char
        pop de
        dec de
        ld (scr_pos_input),de
        ld a,' '
        call write_char
        ld a,10
        ld (delay_char),a
        jr skip_key_checking
not_del:cp 27
        jr nz, not_esc
        
        call clear_lines
        
        ; wait for release of esc
        call wait_esc_rel
        xor a
        ret
not_esc:
        cp 13
        jr nz,not_return
        ; print entered filename
        ld a,(inum)
        ld c,a
        ld b,0
        ld hl,sna_fn+1
        add hl,bc
        ld (hl),0		; zero terminate filename
        
        ; remove cursor
        
        ld de,(scr_pos_input)
        ld a,' '
        ld c,0
        call write_char
        ; wait for release of return
rel_return:
        call keyscan
        
        ld a,(keymap+2)
        and 0x4		; return
        jr z,rel_return
        ld a,(keymap)
        and 0x40		; enter
        jr z,rel_return
        
        ld a,1
        ret
not_return:		
        ld d,a
        ld a,(inum)
        ld c,ixl
        cp c
        jr z,skip_key_checking	; input buffer is full
        ld hl,sna_fn+1
        ld c,a
        ld b,0
        add hl,bc
        ld (hl),d
        inc a
        ld (inum),a
        
        ld a,d
        ld de,(scr_pos_input)
        
        push de
        ld c,0
        call write_char
        pop de
        inc de
        ld (scr_pos_input),de
            
        ld a,20
        ld (delay_char),a
        
        
no_valid_char:

skip_key_checking:
        ld a,(delay_char)
        cp 0
        jr z,delay_done
        dec a
        ld (delay_char),a
delay_done:		
        jp input_loop
clear_lines:
        ld de,0xC000 + 23*80
        ld b,16

clear_loop:
        xor a
        ld l,80
        push de
clear_line:
        ld (de),a
        inc de
        dec l
        jr nz, clear_line
        pop de
        call next_line
        djnz clear_loop
        ret
        
        ; hl = txt ptr
        ; de = ypos,xpos
        ; b = num columns
        ; a = inv. column
disp_columns:
        ld c,b          ; num columns
        ld b,a          ; inv columns
        xor a
ad3:
        add	3
        djnz ad3        ; 
        
        add d           ;
        ld b,c          ; num columns
        ld c,a          ; 
column_loop:
        push bc
        push hl
        
        push de
        ld a,(iy)
        inc iy
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        
        pop de
        push de
        ld a,c
        cp d
        jr nz,not_inv

        ld a,1
        ld (inv_video_flag),a
        call disp_text
        dec a
        ld (inv_video_flag),a
		jr was_inv
not_inv:
        call disp_text
was_inv:
        pop de
        pop hl
        pop bc

        inc d
        inc d
        inc d
        djnz column_loop
        ret		
disp_regs:
        push hl
        push bc
        push de
        
        call disp_text
        
        
        ld a,(iy+1)
        call conv_hex
        ld (ix+0),d
        ld (ix+1),e
        ld a,(iy)
        call conv_hex
        ld (ix+2),d
        ld (ix+3),e
        ld (ix+4),0
        ld hl,temp_buf
        pop	de
        push de
        ld a,d	; reg offset
        add	5
        ld d,a
        ;ld de,0x0502
        call disp_text
        pop de
        pop bc
        pop hl
        
        inc hl	; next register "text"
        inc hl
        inc hl
        inc hl
        inc e	; next text row
        inc iy	;
        inc iy	; next register value
        djnz disp_regs
        ret
setup_crtc:
        
        ld	bc,0xbc0f
crtc_loop:
        out (c),c
        dec	hl
        ld	a,(hl)
        inc	b
        out	(c),a
        dec	b
        dec	c
        jp	p,crtc_loop
        ret

        
        ; entry
        ; a = kbdline
        ; exit
        ; a = hardware key

        org 0x1010
im2_handler:
        ld a,2
        ret
        org 0x1100
im2_jumptable:
        ds 257,0x10
ui_psg_sel:
        db 0x0
ui_psg_regs:
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
ui_crtc_regs:
        db 0x3F, 0x28, 0x2E, 0x8E, 0x26, 0x00, 0x19, 0x1E, 0x00, 0x07, 0x00, 0x00, 0x30, 0x00, 0xC0, 0x00
        
cpc_font:
        db 0,0,0,0,0,0,0,0,0x18,0x18,0x18,0x18,0x18,0,0x18,0,0x6C,0x6C,0x6C,0,0,0,0,0,0x6C
        db 0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0,0x18,0x3E,0x58,0x3C,0x1A,0x7C,0x18,0,0,0xC6,0xCC,0x18
        db 0x30,0x66,0xC6,0,0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0,0x18,0x18,0x30,0,0,0,0,0,0xC
        db 0x18,0x30,0x30,0x30,0x18,0xC,0,0x30,0x18,0xC,0xC,0xC,0x18,0x30,0,0,0x66,0x3C,0xFF
        db 0x3C,0x66,0,0,0,0x18,0x18,0x7E,0x18,0x18,0,0,0,0,0,0,0,0x18,0x18,0x30,0,0,0,0x7E
        db 0,0,0,0,0,0,0,0,0,0x18,0x18,0,6,0xC,0x18,0x30,0x60,0xC0,0x80,0,0x7C,0xC6,0xCE
        db 0xD6,0xE6,0xC6,0x7C,0,0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0,0x3C,0x66,6,0x3C,0x60,0x66
        db 0x7E,0,0x3C,0x66,6,0x1C,6,0x66,0x3C,0,0x1C,0x3C,0x6C,0xCC,0xFE,0xC,0x1E,0,0x7E,0x62
        db 0x60,0x7C,6,0x66,0x3C,0,0x3C,0x66,0x60,0x7C,0x66,0x66,0x3C,0,0x7E,0x66,6,0xC,0x18,0x18
        db 0x18,0,0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0,0x3C,0x66,0x66,0x3E,6,0x66,0x3C,0,0,0
        db 0x18,0x18,0,0x18,0x18,0,0,0,0x18,0x18,0,0x18,0x18,0x30,0xC,0x18,0x30,0x60,0x30,0x18
        db 0xC,0,0,0,0x7E,0,0,0x7E,0,0,0x60,0x30,0x18,0xC,0x18,0x30,0x60,0,0x3C,0x66,0x66
        db 0xC,0x18,0,0x18,0,0x7C,0xC6,0xDE,0xDE,0xDE,0xC0,0x7C,0,0x18,0x3C,0x66,0x66,0x7E,0x66
        db 0x66,0,0xFC,0x66,0x66,0x7C,0x66,0x66,0xFC,0,0x3C,0x66,0xC0,0xC0,0xC0,0x66,0x3C,0,0xF8
        db 0x6C,0x66,0x66,0x66,0x6C,0xF8,0,0xFE,0x62,0x68,0x78,0x68,0x62,0xFE,0,0xFE,0x62,0x68
        db 0x78,0x68,0x60,0xF0,0,0x3C,0x66,0xC0,0xC0,0xCE,0x66,0x3E,0,0x66,0x66,0x66,0x7E,0x66
        db 0x66,0x66,0,0x7E,0x18,0x18,0x18,0x18,0x18,0x7E,0,0x1E,0xC,0xC,0xC,0xCC,0xCC,0x78,0
        db 0xE6,0x66,0x6C,0x78,0x6C,0x66,0xE6,0,0xF0,0x60,0x60,0x60,0x62,0x66,0xFE,0,0xC6,0xEE
        db 0xFE,0xFE,0xD6,0xC6,0xC6,0,0xC6,0xE6,0xF6,0xDE,0xCE,0xC6,0xC6,0,0x38,0x6C,0xC6,0xC6
        db 0xC6,0x6C,0x38,0,0xFC,0x66,0x66,0x7C,0x60,0x60,0xF0,0,0x38,0x6C,0xC6,0xC6,0xDA,0xCC
        db 0x76,0,0xFC,0x66,0x66,0x7C,0x6C,0x66,0xE6,0,0x3C,0x66,0x60,0x3C,6,0x66,0x3C,0,0x7E
        db 0x5A,0x18,0x18,0x18,0x18,0x3C,0,0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0,0x66,0x66,0x66
        db 0x66,0x66,0x3C,0x18,0,0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0,0xC6,0x6C,0x38,0x38,0x6C
        db 0xC6,0xC6,0,0x66,0x66,0x66,0x3C,0x18,0x18,0x3C,0,0xFE,0xC6,0x8C,0x18,0x32,0x66,0xFE
        db 0,0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0,0xC0,0x60,0x30,0x18,0xC,6,2,0,0x3C,0xC,0xC,0xC
        db 0xC,0xC,0x3C,0,0x18,0x3C,0x7E,0x18,0x18,0x18,0x18,0,0,0,0,0,0,0,0,0xFF,0x30,0x18
        db 0xC,0,0,0,0,0,0,0,0x78,0xC,0x7C,0xCC,0x76,0,0xE0,0x60,0x7C,0x66,0x66,0x66,0xDC
        db 0,0,0,0x3C,0x66,0x60,0x66,0x3C,0,0x1C,0xC,0x7C,0xCC,0xCC,0xCC,0x76,0,0,0,0x3C,0x66
        db 0x7E,0x60,0x3C,0,0x1C,0x36,0x30,0x78,0x30,0x30,0x78,0,0,0,0x3E,0x66,0x66,0x3E,6,0x7C
        db 0xE0,0x60,0x6C,0x76,0x66,0x66,0xE6,0,0x18,0,0x38,0x18,0x18,0x18,0x3C,0,6,0,0xE,6
        db 6,0x66,0x66,0x3C,0xE0,0x60,0x66,0x6C,0x78,0x6C,0xE6,0,0x38,0x18,0x18,0x18,0x18,0x18
        db 0x3C,0,0,0,0x6C,0xFE,0xD6,0xD6,0xC6,0,0,0,0xDC,0x66,0x66,0x66,0x66,0,0,0,0x3C,0x66
        db 0x66,0x66,0x3C,0,0,0,0xDC,0x66,0x66,0x7C,0x60,0xF0,0,0,0x76,0xCC,0xCC,0x7C,0xC,0x1E
        db 0,0,0xDC,0x76,0x60,0x60,0xF0,0,0,0,0x3C,0x60,0x3C,6,0x7C,0,0x30,0x30,0x7C,0x30,0x30
        db 0x36,0x1C,0,0,0,0x66,0x66,0x66,0x66,0x3E,0,0,0,0x66,0x66,0x66,0x3C,0x18,0,0,0,0xC6
        db 0xD6,0xD6,0xFE,0x6C,0,0,0,0xC6,0x6C,0x38,0x6C,0xC6,0,0,0,0x66,0x66,0x66,0x3E,6,0x7C
        db 0,0,0x7E,0x4C,0x18,0x32,0x7E,0,0xE,0x18,0x18,0x70,0x18,0x18,0xE,0,0x18,0x18,0x18
        db 0x18,0x18,0x18,0x18,0,0x70,0x18,0x18,0xE,0x18,0x18,0x70,0,0x76,0xDC,0,0,0,0,0,0
        db 0xCC,0x33,0xCC,0x33,0xCC,0x33,0xCC,0x33

cmd_open:	db 16
            db C_OPEN&0xFF, C_OPEN>>8, FA_CREATE_ALWAYS | FA_REALMODE |FA_WRITE
            db "/m4/tmp1.bin",0

cmd_open2:	db 16
            db C_OPEN&0xFF, C_OPEN>>8, FA_READ | FA_REALMODE
temp_fn:	db "/m4/tmp1.bin",0

cmd_open3:	db 16
            db C_OPEN&0xFF, C_OPEN>>8, FA_READ | FA_WRITE | FA_REALMODE
            db "/m4/tmp1.bin",0

        ; entry 
        ; A
        ; exit
        ; DE = ascii hex
conv_hex:
        push af
        push bc
        ld	b,a
        srl	a
        srl	a
        srl	a
        srl	a
        add	0x90
        daa
        adc	0x40
        daa
        ld d,a
        ld a,b
        and	0x0f
        add	0x90
        daa
        adc	0x40
        daa
        ld e,a
        pop bc
        pop af
        ret

keyscan:		
        push hl
        push bc
        push de		
        ld hl,keymap    ;3
        ld bc,0xf782     ;3
        out (c),c       ;4
        ld bc,0xf40e     ;3
        ld e,b          ;1
        out (c),c       ;4
        ld bc,0xf6c0     ;3
        ld d,b          ;1
        out (c),c       ;4
        ld c,0          ;2
        out (c),c       ;4
        ld bc,0xf792     ;3
        out (c),c       ;4
        ld a,0x40        ;2
        ld c,0x4a        ;2 44
kloop:  ld b,d          ;1
        out (c),a       ;4 select line
        ld b,e          ;1
        ini             ;5 read bits and write into KEYMAP
        inc a           ;1
        cp c            ;1
        jr c,kloop       ;2/3 9*16+1*15=159
        ld bc,0xf782     ;3
        out (c),c       ;4		
        pop de
        pop bc
        pop hl
        ret

check_nokeypressed:
        push hl
        push bc
        push af
nokey_init:
        ld hl,keymap
        ld b,10
nokey_loop:
        ld a,(hl)
        cp 0xff
        jr nz,wait_key_released
        inc hl
        djnz nokey_loop
        pop af
        pop bc
        pop hl
        ret
wait_key_released:
        call keyscan
        jr nokey_init

        ; hl = text address
        ; e = line
        ; d = column
disp_text:
        push af
        push bc
        ex	de,hl
		ld	c,h
        push bc
        ld	a,l				; line num
        ld	hl,0			; 
        ld	bc,80			; screen width in bytes
mult:	cp 0
        jr z, mult_done
        add hl,bc
        dec	a
        jr	mult
mult_done:		
        pop bc    
        ld	b,0xC0
        add	hl,bc		; line + C000 + column
        ex	de,hl
disp_loop:
        ld	a,(hl)
        or	a
        jr z,end_disp_loop
        cp 7            ; 7 is BELL in ASCII but also INV VIDEO in ANSI
        jr z,inv_video

        ld a,(inv_video_flag)
        or a
        jr nz,inv_char

        ld a,(hl)
        ld c,0
        call write_char
        jr cont_loop
inv_char:
        ld a,(hl)
        ld c,255                ; force inv video
        call write_char         ; can be used always instead of write_char
        jr cont_loop
inv_video:
        ld a,(inv_video_flag)
        xor 1
        ld (inv_video_flag),a
        dec de        
cont_loop:
        inc	de
        inc	hl
        jr disp_loop
end_disp_loop:
        pop bc
        pop af
        ret

        ; a = char, if bit 7 is set then inv video
        ; if c = 255, then inv video as well
        ; de = screen address
write_char:
        push bc
        push hl
        push de
                
        cp 0x80
        jr c, no_char_inv
        ld c,0xFF
        xor 0x80
no_char_inv:
        sub	32
        ld	l,a
        ld	h,0
        add	hl,hl	; * 2
        add	hl,hl	; * 4
        add	hl,hl	; * 8
        push bc
        ld	bc,cpc_font
        add	hl,bc
        pop bc
        ld	b,8
hloop:
        ld a,c
        inc a           ; check for video inversion
        ld a,(hl)
        jr nz,no_inv
        xor c         ; inv video
no_inv: ld	(de),a
        ld	a,d
        add	8
        ld	d,a
        and	0x38
        jr	nz,line_ok
        ld	a,d
        sub	0x40
        ld	d,a
        ld	a,e
        add	80		; SCREEN_WIDTH
        ld	e,a
        jr	nc, line_ok
        inc	d
        ld	a,d
        and	7
        jr	nz, line_ok
        ld	a,d
        sub	8
        ld	d,a	
line_ok:
        inc	hl
        djnz	hloop
        pop de
        pop hl
        pop bc
        ret

        ; entry
        ; hl -> ascii value
        ; a -> len of value
        ; return
        ; hl = binary value
ascii2bin:
        ld b,0
        ld c,a
        add hl,bc
        dec hl
        ex de,hl
        ld hl,0
        
        ld a,(de)
        cp 58
        jp c,nib_less1
        sub 55
        jr nib_done1
nib_less1:	
        sub 48
nib_done1:	
        ld l,a
        dec de
        dec c
        ret z
        ld a,(de)
        cp 58
        jp c,nib_less2
        sub 55
        jr nib_done2
nib_less2:
        sub 48
nib_done2:	
        sla a		
        sla a
        sla a
        sla a
        or l
        ld l,a
        dec de
        dec c
        ret z
        
        ld a,(de)
        cp 58
        jp c,nib_less3
        sub 55
        jr nib_done3
nib_less3:	
        sub 48
nib_done3:	
        ld h,a
        dec de
        dec c
        ret z
        ld a,(de)
        cp 58
        jp c,nib_less4
        sub 55
        jr nib_done4
nib_less4:
        sub 48
nib_done4:
        sla a		
        sla a
        sla a
        sla a
        or h
        ld h,a
        ret
        

        ; e = 64 / 128
set_dump_size:
        
        
        ; copy regs to ROM
        
        ld	bc,DATAPORT					; data out port
        out (c),c
        ld	a, C_ROMWRITE & 0xFF		;
        out	(c),a						; command lo
        ld	a, C_ROMWRITE>>8			;
        out	(c),a						; command	hi
        ld a,memdump_sz&0xFF
        out	(c),a						; rom dest addr
        ld a,memdump_sz>>8
        out	(c),a						; rom dest addr => snamem
        ld	a,1
        out	(c),a						; size
        xor	a
        out	(c),a						; size 0001
        ld a,255
        out	(c),a						; 1 bank (0 = M4 ROM, 255 = nmi rom)
        out (c),e						; write memdump size
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ret
        
        
        ; ix = poke table
        ; a = num pokes
        
apply_pokes:
        ld d,a
        ; open file for read and write
    
        ld	hl,cmd_open3
        ld	bc,DATAPORT
        ld	a,17
rsendloop3:
        inc	b
        outi
        dec	a
        jr	nz, rsendloop3
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ld a,(m4romnum)
        ld bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        ld	e,(iy+3)		; get fd
        
app_poke_loop:		
        ; seek to correct offset
        
        ld l,(ix)
        ld h,(ix+1)
        ld bc,0x100			; offset header + poke offset
        add hl,bc
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_SEEK&0xFF	
        out	(c),a
        ld	a,C_SEEK>>8	
        out	(c),a
        push de
        out	(c),e			; fd
        out	(c),l
        out	(c),h			; offset
        xor a
        out	(c),a
        out	(c),a			; offset hi word = 0
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ; write new byte
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_WRITE2&0xFF	
        out	(c),a
        ld	a,C_WRITE2>>8	
        out	(c),a		
        pop de		
        out	(c),e			; fd
        ld a,1
        out	(c),a			; size 1
        xor a
        out	(c),a			; size 0x0001
        ld a,(ix+2)
        out (c),a			; new val
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        inc ix
        inc ix
        inc ix
        dec d				; decrease pokes
        jr nz, app_poke_loop
        
        ; close file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ret

;
; DISPLAY MEMORY
; 
display_memory_input:
        ld hl,txt_address
        ld de,L_DISPMEM
        call disp_text
        ld iy,key_poke_translate
        ld ix,I_DISPMEM
        call get_input
        ret z
        ld hl,sna_fn+1
        ld a,(inum)
        call ascii2bin

display_memory:
        push af
        push bc
        push de
        push hl
        push ix
        push iy
        
        push hl
        sra l
        sra l
        sra l
        sra l
        sla l
        sla l
        sla l
        sla l                   ; round the address to the nearest 0x10 address
        pop bc
        ld a,c
        sub a,l                 ; offset between required address and rounded address

        ld (dispmem_offset),a   ; keep the address offset to highlight the address that was required
        ld (dispmem_address),hl ; hl = memory address

        call readfile	       ; read 64 bytes hardcoded to temp_buf2
        ld bc,0x7F8A
        out (c),c

        ld hl,L_DISPMEMDUMP
        ld (dispmem_line),hl

        ld hl,temp_buf2         ; memory to dump
        xor a                   ; row number
        ld c,0                  ; global memory offset
outer_loop:
        push af
        push hl        
        
        ld ix,temp_buf    ; printable text buffer hex
        ld (ix+53),32
        ld iy,temp_buf+54 ; printable text ascii
        ld (iy+16),0

        ld a,(dispmem_address+1)
        call conv_hex
        ld (ix),d
        ld (ix+1),e
        ld a,(dispmem_address)
        call conv_hex
        ld (ix+2),d
        ld (ix+3),e
        ld (ix+4),':'
        ld (ix+5),' '
        inc ix
        inc ix
        inc ix
        inc ix
        inc ix
        inc ix

        ld b,16           ; how many bytes to display

conv_loop_hex:
        push bc
        ld a,(hl)
        call conv_hex
        cp 32
        jr c,ko_to_print
        cp 128
        jr c,ok_to_print
ko_to_print:        
        ld a,'.'
ok_to_print:        
        ld (iy),a               ; value as ascii 
        ld a,(dispmem_offset)
        cp c
        jr nz,no_highlight

        ld a,d
        or 128
        ld d,a
        ld a,e
        or 128
        ld e,a

no_highlight:
        ld (ix),d
        ld (ix+1),e
        ld (ix+2),32
        
        inc ix
        inc ix
        inc ix
        inc iy
        inc hl
        pop bc
        inc c
        djnz conv_loop_hex

        ld hl,temp_buf
        ld de,(dispmem_line)
        push de
        call disp_text
        pop de
        inc de
        ld (dispmem_line),de

        ld bc,0x10              ; prepare next row
        ld hl,(dispmem_address)  ; offset + 16 bytes
        add hl,bc
        ld (dispmem_address),hl
        pop hl                  ; next 16 bytes in buffer
        add hl,bc        
        pop af
        inc a
        cp N_DISPMEM
        jp nz,outer_loop
        pop iy
        pop ix
        pop hl
        pop de
        pop bc
        pop af
        ret



        ; hl = offset		
readfile:
        push hl
        ; open file for read and write
    
        ld	hl,cmd_open2
        ld	bc,DATAPORT
        ld	a,17
rsendloop4:
        inc	b
        outi
        dec	a
        jr	nz, rsendloop4
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ld a,(m4romnum)
        ld bc, 0xDF00
        out (c),a			; select M4 rom
        ld	bc, 0x7F82		; enable upper and lower rom
        out (c),c
        ld	iy,(0xFF02)		; get ROM response table
        ld	e,(iy+3)		; get fd
        pop hl
    
        ; seek to correct offset
        
        ld bc,0x100			; offset header + offset
        add hl,bc
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_SEEK&0xFF	
        out	(c),a
        ld	a,C_SEEK>>8	
        out	(c),a
        push de
        out	(c),e			; fd
        out	(c),l
        out	(c),h			; offset
        xor a
        out	(c),a
        out	(c),a			; offset hi word = 0
        
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
    

        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_READ2&0xFF	
        out	(c),a
        ld	a,C_READ2>>8	
        out	(c),a		
        pop de		
        out	(c),e			; fd
        ld a,N_DISPMEMBYTES
        out	(c),a			; size 
        xor a
        out	(c),a			; size
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        
        ; read data
        push de
        ld hl,(0xFF02)
        ld de,8
        add	hl,de						; point to response data
        ld de,temp_buf2
        ld bc,N_DISPMEMBYTES
        ldir
        pop de
        ; close file
        
        ld	bc,DATAPORT
        out	(c),c			; ignore first byte
        ld	a,C_CLOSE&0xFF	
        out	(c),a
        ld	a,C_CLOSE>>8	
        out	(c),a			
        out	(c),e			; fd
        ld	b,ACKPORT>>8	; kick command
        out	(c),c
        ret
        
next_line:
        ld	a,d
        add	8
        ld	d,a
        and	0x38
        ret nz
        ld	a,d
        sub	0x40
        ld	d,a
        ld	a,e
        add	80		; SCREEN_WIDTH
        ld	e,a
        ret nc
        inc	d
        ld	a,d
        and	7
        ret nz
        ld	a,d
        sub	8
        ld	d,a	
        ret

check_menu_keys:        
        push bc
        ld c,1
        ld a,(keymap+7)
        and 16              ; S
        jr z,menu_key_pressed
        inc c
        ld a,(keymap+4)
        and 16              ; L
        jr z,menu_key_pressed
        inc c
        ld a,(keymap+7)
        and 64              ; C
        jr z,menu_key_pressed
        inc c
        ld a,(keymap+3)
        and 8               ; P
        jr z,menu_key_pressed
        inc c
        ld a,(keymap+7)
        and 32              ; D
        jr z,menu_key_pressed
        inc c
        ld a,(keymap+6)
        and 4               ; R
        jr z,menu_key_pressed
        xor a               ; no menu key pressed
        pop bc
        ret
menu_key_pressed:
        call check_nokeypressed
        ld a,c
        pop bc
        ret

clear_pointer:
        push bc
        push de
        push af                
        ld de,(last_scr_y)
        push de
        ld a,' '
        ld c,0
        call write_char
        pop de
        inc de
        push de
        ld a,' '
        call write_char
        pop de
        inc de
        ld a,' '
        call write_char
        pop af
        pop de
        pop bc
        ret

draw_pointer:
        push af
        push bc
        push de
        push hl
        ld de,0xC000 + L_MENU_Y*80 + L_MENU_X
        ld a,(ypos)
        cp 0
        jr z,is_first_item
        ld bc,80
        ld hl,0
yline:	add hl,bc
        dec a
        jr nz,yline
        add hl,de
        ex de,hl
is_first_item:	
        ld (last_scr_y),de        
        ld b,3
sel_anim:
        push bc
        push de
        ld a,(anim_count)
        ld h,'>'
        cp b
        jr nz, not_b
        ld h,' '
not_b:
        ex af,af'	;'
        ld a,h
        ld c,0
        call write_char
        pop de
        pop bc
        ld hl,1
        add hl,de
        ex de,hl
        djnz sel_anim
    
        ld a,(anim_count)
        inc a
        cp 4
        jr nz, not_4
        xor a
not_4:
        ld (anim_count),a
        pop hl
        pop de
        pop bc
        pop af        
        ret

; print reg A on screen
debug_a:
        push af
        push bc
        push de
        push hl
        call conv_hex
        ld a,d
        push de
        ld de,0xC277
        ld c,255
        call write_char
        pop de
        ld a,e
        ld de,0xC278
        call write_char
        pop hl
        pop de
        pop bc
        pop af
        ret

txt_title:
        IFDEF DEBUG
            db "M4 Hack Dbg"
            TIMESTAMP
        ELSE
            db "M4 Hack Menu / Duke 2018-2021"
        ENDIF
        db 0
            
txt_build        
        db 0

txt_z80regs:
        db "Z80 regs",0

txt_regs1:
        db "AF ",0,"BC ",0,"DE ",0,"HL ",0,"SP ",0,"PC ",0
        db "AF'",0,"BC'",0,"DE'",0,"HL'",0,"IX ",0,"IY ",0
txt_r:
        db "R  ",0
txt_i:
        db "I  ",0
txt_im:
        db "IM ",0
txt_pal:
        db "Pal.",0,"PSG",0,"CRTC",0
txt_rmr:
        db "RMR",0,"MMR",0,"ROM",0
txt_ppi:
        db "PPIA",0,"PPIB",0,"PPIC",0,"PPICR",0
txt_ints:
        db "INT",0
txt_64KB:
        db "64K ",0
txt_128KB:
        db "128K",0
txt_menu:
        db "(S)ave snapshot",0
        db "(L)oad snapshot",0
        db "(C)hange dump size:",0
        db "(P)okes",0
        db "(D)isplay memory",0
        db "(R)esume",0
txt_filename:
        db "Enter filename: ",0
txt_save:
        db "Saving:",0
txt_load:
        db "Loading:",0
txt_qwerty:
        db "KEYB   QW",0
txt_azerty:
        db "KEYB   AZ",0
txt_success:
        db "  Success!",0
txt_failed:
        db "  Failed!",0
txt_address:
        db "Addr:                 ",0
txt_val:				
        db "Val:",0
txt_applied:				
        db "Pokes applied!",0		
key_translate:
        db '.', 13,'3','6','9',0x0,0x0,0x0
        db '0','2','1','5','8','7',0x0,0x0
        db 0x0, 39,0x0,'4',']', 13,'[',0x0
        db '.',0x0,0x0, 59,'p','@','-','^'
        db ',','m','k','l','i','o','9','0'
        db ' ','n','j','h','y','u','7','8'
        db 'v','b','f','g','t','r','5','6'
        db 'x','c','d','s','w','e','3','4'
        db 'z',0x0,'a',0x0,'q', 27,'2','1'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
key_translate_shift:
        db '.', 13,'3','6','9',0x0,0x0,0x0
        db '0','2','1','5','8','7',0x0,0x0
        db 0x0,'/',0x0,'4','}', 13,'{',0x0
        db 0x0,'/',0x0,'+','P',0x0,'=','^'
        db  60,'M','K','L','I','O',')','_'
        db ' ','N','J','H','Y','U',39,'('
        db 'V','B','F','G','T','R','%','&'
        db 'X','C','D','S','W','E','#','$'
        db 'Z',0x0,'A',0x0,'Q', 27,0x0,'!'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
key_poke_translate:
        db 0x0, 13,'3','6','9',0x0,0x0,0x0
        db '0','2','1','5','8','7',0x0,0x0
        db 0x0,0x0,0x0,'4',0x0, 13,0x0,0x0
        db 0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0
        db 0x0,0x0,0x0,0x0,0x0,0x0,'9','0'
        db 0x0,0x0,0x0,0x0,0x0,0x0,'7','8'
        db 0x0,'B','F',0x0,0x0,0x0,'5','6'
        db 0x0,'C','D',0x0,0x0,'E','3','4'
        db 0x0,0x0,'A',0x0,0x0, 27,'2','1'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
        
key_translate_azerty:
        db '.', 13,'3','6','9',0x0,0x0,0x0  ; numeric keys
        db '0','2','1','5','8','7',0x0,0x0  ; numeric keys
        db 0x0,0x0,0x0,'4','#', 13,0x0,0x0
        db 0x0,0x0,'m',0x0,'p','^',0x0,'-'
        db 0x0,0x0,'k','l','i','o',0x0,'a'
        db 0x0,'n','j','h','y','u','e',0x0
        db 'v','b','f','g','t','r',0x0,0x0
        db 'x','c','d','s','z','e',0x0, 39
        db 'w',0x0,'q',0x0,'a', 27,'e','&'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
key_translate_shift_azerty:
        db '.', 13,'3','6','9',0x0,0x0,0x0 ; numeric keys
        db '0','2','1','5','8','7',0x0,0x0 ; numeric keys
        db 0x0,0x0,0x0,'4',0x0, 13,0x0,0x0
        db '/','+','M',0x0,'P',0x0,0x0,0x0
        db '.',0x0,'K','L','I','O','9','0'
        db 0x0,'N','J','H','Y','U','7','8'
        db 'V','B','F','G','T','R','5','6'
        db 'X','C','D','S','Z','E','3','4'
        db 'W',0x0,'Q',0x0,'A', 27,'2','1'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
        
key_poke_translate_azerty:
        db 0x0, 13,'3','6','9',0x0,0x0,0x0
        db '0','2','1','5','8','7',0x0,0x0
        db 0x0,0x0,0x0,'4',0x0, 13,0x0,0x0
        db 0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0
        db 0x0,0x0,0x0,0x0,0x0,0x0,'9','0'
        db 0x0,0x0,0x0,0x0,0x0,0x0,'7','8'
        db 0x0,'B','F',0x0,0x0,0x0,'5','6'
        db 0x0,'C','D',0x0,0x0,'E','3','4'
        db 0x0,0x0,0x0,0x0,'A', 27,'2','1'
        db 0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x0
        
sna_temp:
        db "/M4SNAP.SNA",0
ram_code:
        org 0x8000,$
        
endless:
        jr	endless
ypos:	db 0
anim_count:db 0
poke_count:db 0
cur_toggle: db 0
cur_flash: db 0
frame_count:db 0
last_char: db 0
inum: db 0
inv_video_flag: db 0
delay_char:db 0
last_scr_y:	dw 0
scr_pos_input: dw 0
keyb_layout_offset: dw 0
sna_fn:	ds 64

dispmem_line: dw 0
dispmem_address: dw 0
dispmem_offset: db 0

keymap: ds 10
temp_buf:
        ds 256
temp_buf2:
        ds 256
        org	$
ram_code_end:
