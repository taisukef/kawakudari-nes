  .inesprg 1 ; program bank cnt
  .ineschr 1 ; chr bank cnt
  .inesmir 1 ; mirror 0:horizontal 1:vertical
  .inesmap 0 ; mapper no

VRAM_DATA equ $2007     ; vram data register
VRAM_AD   equ $2006     ; vram address register
CTRL1     equ $4016     ; controller 1

SPRITE    equ $0300     ; on RAM for OAM
SPRITE_Y  equ $0300     ; on RAM for OAM
SPRITE_T  equ $0301     ; on RAM for OAM
SPRITE_A  equ $0302     ; on RAM for OAM
SPRITE_X  equ $0303     ; on RAM for OAM

SP_CAT    equ SPRITE + 63 * 4 ; cat
SP_ENEMY  equ SPRITE
LAST_ENEMY equ 30 * 4

  .bank 1
  .org $fffa
  .dw 0     ; VBlank int
  .dw reset ; reset int
  .dw 0     ; break int

; zeropage
  .bank 0
  .org $0000
rnd_seed    ds 1
frame       ds 1
next_enemy  ds 1

; main
  .org $8000

reset:
  sei ; disable int
  cld ; clear decimal mode
  ldx #$ff
  txs ; init stack pointer

init:
  jsr zeropage_init
  jsr sound_init
  jsr wait_vsync
  jsr screen_off
  jsr palette_init
  jsr cls

  jsr screen_on
  jsr sprite_init
  jsr scroll_zero


game_init:
  jsr zeropage_init
  jsr wait_vsync
  jsr sprite_clear
  
  jsr sprite_put

game_loop:

control:
  jsr input_start1
  lda CTRL1 ; A
  lda CTRL1 ; B
  lda CTRL1 ; SELECT
  lda CTRL1 ; START
  lda CTRL1 ; UP
  lda CTRL1 ; DOWN
  lda CTRL1 ; LEFT
  and #1
  beq control_skip_left
  ldx SP_CAT + 3
  dex
  stx SP_CAT + 3
control_skip_left:
  lda CTRL1 ; RIGHT
  and #1
  beq control_skip_right
  ldx SP_CAT + 3
  inx
  stx SP_CAT + 3
control_skip_right:


enemy:
  lda frame
  clc
  adc #1
  sta frame
  and #7
  bne enemy_skip1

  lda next_enemy
  cmp #120 ;LAST_ENEMY
  beq enemy_skip1
  tax
  lda #220 ; Y
  sta SP_ENEMY + 0, x
  lda #42 ; *
  sta SP_ENEMY + 1, x
  lda #0; T
  sta SP_ENEMY + 2, x
  jsr rnd
  sta SP_ENEMY + 3, x
  inx
  inx
  inx
  inx
  stx next_enemy

enemy_skip1:

  ldy #252 ; 63 * 4 SP_CAT

  ldx next_enemy
enemy_loop1:
  dex
  bmi enemy_skip2
  dex
  dex
  dex
  ; move
  lda SP_ENEMY + 0, x
  clc
  ;sbc #0 ; y--
  sbc #1 ; y -= 2
  sta SP_ENEMY + 0, x

  ; hit check
  jsr sprite_hit_check
  bcc enemy_skip3
  ; gameover
  jsr sound_hit
  ldx #60
  jsr waitx
  jmp game_init
enemy_skip3:

  jmp enemy_loop1
enemy_skip2:

  jsr wait_vsync

  jsr sprite_dma
  jmp game_loop

; sub routines ----------------------------------------------------------------------------------

rnd: ; *5+3
  lda rnd_seed
  asl a
  asl a
  clc
  adc rnd_seed
  clc
  adc #3
  sta rnd_seed
  rts

screen_off:
  ldx #%00000000
  sta $2000
  sta $2001
  rts

screen_on:
  ; screen on
  ;lda  #$10 ; BG
  ;lda  #$08 ; SPRITE 
  lda #%00000000 ;#%VPHBSINN (vBlank int, PPU type slave, sprite size 8x16, bg no, sprite no, vram +32, main screen(2bit))
  sta  $2000
  ;   #%BGRSBMmC (B:blue, G:green, R:red, S:sprite, BG:bg, M:left limit sprite, m:left limit BG, C:color no)
  lda  #%00011110
  sta  $2001
  rts

sprite_init:
  ; DMA setup
  lda #0
  sta $2003
  rts

sprite_put: ; Y, T(vertical_flip, horizontal_flip, background, 0, 0, 0, pallete1, pallete0), A, X
  lda #30 ; Y
  sta SP_CAT + 0
  lda #236 ; cat
  sta SP_CAT + 1
  lda #0; T
  sta SP_CAT + 2
  lda #120 ; X
  sta SP_CAT + 3
  rts

sprite_hit_check: ; y, x -> carry is hit
  lda SPRITE_Y, x
  clc
  sbc #5
  cmp SPRITE_Y, y
  bcs sprite_hit_check_no ; y.Y - 8 >= x.Y -> not hit
  adc #10
  cmp SPRITE_Y, y
  bcc sprite_hit_check_no ; y.Y + 8 < x.Y -> not hit
  lda SPRITE_X, x
  sbc #5
  cmp SPRITE_X, y
  bcs sprite_hit_check_no ; y.X >= x.X + 8 -> not hit
  adc #10
  cmp SPRITE_X, y
  bcc sprite_hit_check_no ; y.X + 8 < x.X -> not hit
  sec
  rts
sprite_hit_check_no:
  clc
  rts

sprite_clear:
  lda #0
  ldx #0
sprite_clear_loop:
  sta $300, x
  inx
  bne sprite_clear_loop
  rts

sprite_dma:
  lda #3 ; bank 3 ($0300)
  sta $4014 ; copy to OMA
  rts

sound_init:
  lda #%00001111  ; 矩形波チャンネル1
  sta $4015    ; サウンドレジスタ
  rts

sound_test:
  ; play SE1 (矩形波1)
  ;     DDLCVVVV (DD=duty(00: 87.5%, 01: 75%, 10: 50%, 11: 25%), L=再生時間カウンタ, C=volume fix, VVVV=volume)
  lda #%10101111
  sta $4000
  ;   #%EPPPSSSS (E=sweeve, PPP=length, SSSS=shift)
  lda #%00000000
  sta $4001
  
  ; CPUのクロック周波数 / (再生周波数 * 32) - 1
  ; clock = 1.789773MHz = 1789773Hz, 440Hz ラ, 1789773/(440*32)-1 = 126.11
  ; clock = 1.789773MHz = 1789773Hz, 220Hz ラ, 1789773/(220*32)-1 = 253.23
  ; clock = 1.789773MHz = 1789773Hz, 110Hz ラ, 1789773/(110*32)-1 = 507.45
  ;   #%TTTTTTTT T下位3bit
  lda #%00000000
  sta $4002 ; サウンドレジスタ
  ;   #%LLLLLTTT 長さL, T上位3bit
  lda #%00001001
  sta $4003 ; サウンドレジスタ
  rts

sound_hit:
  ; play SE1 (ノイズ)
  ;     --cevvvv (c=再生時間カウンタ, e=effect, v=volume)
  lda #%00011111
  sta $400C
  ;     r---ssss (r=乱数種別, s=サンプリングレート)
  lda #%00001010
  sta $400E
  ;     ttttt--- (t=再生時間)
  lda #%00111000
  sta $400F

  ; play SE2 (矩形波2)
  ;     ddcevvvv (d=duty, c=再生時間カウンタ, e=effect, v=volume)
  lda #%10111111
  sta $4004
  ;     csssmrrr (c=周波数変化, s=speed, m=method, r=range)
  lda #%11110010
  sta $4005
  ;     kkkkkkkk (k=音程周波数の下位8bit)
  lda #%01101000
  sta $4006
  ;     tttttkkk (t=再生時間, k=音程周波数の上位3bit)
  lda #%10001010
  sta $4007
  rts

cls: ; 32x30 = 256x240px
  jsr bg_clear
  jsr attr_clear
  jsr sprite_clear
  rts

bg_clear:
  lda #$20
  ldx #$00
  jsr vram_set
  ldx #0
  lda #0
  jsr  vram_fill
  jsr  vram_fill
  jsr  vram_fill
  ldx #192
  jsr  vram_fill
  rts

attr_clear:
  lda  #$23
  ldx  #$c0 ; clear area color (fill 00h) // 64byte 1byteで4x4の16ブロック(1ブロック 8x8)の属性、1blockあたり2bit(4パレットから選択)
  jsr  vram_set

  ; == 64byte $40
  ldx  #$40
  lda  #$0 ; attribute
  jsr   vram_fill
  rts

input_start1:
  lda #1
  sta CTRL1
  lda #0
  sta CTRL1
  rts

vram_set:  ;  vram adrs set ;  high a reg , low x reg
  sta  VRAM_AD    ;set high
  stx  VRAM_AD    ;set low
  rts

vram_fill: ; fill a size x
  sta  VRAM_DATA
  dex
  bne  vram_fill
  rts

palette_init:
  ; set VRAM address <= $3f00
  lda #$3f
  sta VRAM_AD
  lda #$00
  sta VRAM_AD

  ldx #0
palette_init_loop:
  lda palette_data, x
  sta $2007 ; mapped VRAM
  inx
  cpx #32
  bne palette_init_loop
  rts

scroll_zero:
  ;スクロールレジスタをリセット
  lda #$0
  sta $2005 ;X座標
  sta $2005 ;Y座標
  rts

zeropage_init:
  lda #0
  tax
zeropage_init_loop:
  sta <$00, x
  inx
  bne zeropage_init_loop
  rts

wait_vsync: ; 垂直同期待ち
  lda $2002
  bpl wait_vsync
  rts

waitx:
  jsr wait_vsync
  dex
  bne waitx
  rts

; data
palette_data:
  ; BG
  .db  $00, $30, $00, $00
  .db  $00, $0f, $00, $00
  .db  $00, $0f, $00, $00
  .db  $00, $0f, $00, $00
  ; SPRITE
  .db  $0f, $30, $00, $00
  .db  $00, $0f, $00, $00
  .db  $00, $0f, $00, $00
  .db  $00, $0f, $00, $00

; chr
 .bank 2
 .org $0000
  .incbin "ichigojam-charmap-jp.chr"
