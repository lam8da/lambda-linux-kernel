  BOOTSEG equ 07c0H     ; 引导扇区（本程序）被BIOS加载到内存0x7c00处。
  SYSSEG  equ 01000H    ; 内核（head）先加载到0x10000处，然后移动到0x0处。
  SYSLEN  equ 17        ; 内核占用的最大磁盘扇区数。(不明白这个大小是怎么确定的)

start:
  jmp BOOTSEG:go        ; 段间跳转至0x7c0:go处。当本程序刚运行时所有段寄存器值
                        ; 均为0。该跳转语句会把CS寄存器加载为0x7c0（原为0）。
go:
  mov ax, cs            ; 让DS、ES和SS都指向0x7c0段。
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov sp, 0x400         ; 设置临时栈指针。其值需大于程序末端并有一定空间即可。

  ; 加载内核代码到内存0x10000开始处。
  ; 本程序是假设引导代码和程序都放在软盘上
  ; 读取软盘的第2个扇区开始的[SYSLEN]个扇区的数据，读到[SYSSEG]:0处，第1个扇区是
  ; 引导扇区！
load_system:
  ; 利用BIOS中断int 0x13功能2从引导盘读取head代码。
  ; mov dx, 0x80          ; 从第一个硬盘读取
  mov dx, 0x00          ; 从第一个软盘读取
  mov cx, 2             ; 从第二个扇区读取。其中：
                        ; CL - 位7、6是磁道号高2位，位5～0起始扇区号（从1计）。
                        ; DH - 磁头号；DL - 驱动器号；CH - 10位磁道号低8位；
  mov ax, SYSSEG
  mov es, ax  
  mov bx, 0             ; ES:BX - 读入缓冲区位置（0x1000:0x0000）。
  mov ax, 0x200+SYSLEN  ; AH - 读扇区功能号；AL - 需读的扇区数（17）。
  int 0x13
  jnc ok_load           ; 若没有发生错误则跳转继续运行，否则死循环。
die:  jmp die

  ; 把内核代码移动到内存0开始处。共移动8KB（内核长度不超过8KB）。不用担心内核代
  ; 码会把当前段当前执行的代码覆盖，因为当前段从绝对地址0x7c00=31KB处开始。
ok_load:
  cli                   ; 关中断
  mov ax, SYSSEG        ; 移动开始位置DS:SI = 0x1000:0；目的位置ES:DI=0:0。
  mov ds, ax
  xor ax, ax
  mov es, ax
  mov cx, 0x1000        ; 设置共移动4K次，每次移动一个字（word）。
  sub si, si
  sub di, di
  rep movsw             ; 执行重复移动指令。

  ; 加载IDT和GDT基地址寄存器IDTR和GDTR。
  mov ax, BOOTSEG
  mov ds, ax            ; 让DS重新指向0x7c0段。
  lidt [idt_48]         ; 加载IDTR。6字节操作数=2字节表长度+4字节线性基地址
  lgdt [gdt_48]         ; 加载GDTR。6字节操作数=2字节表长度+4字节线性基地址

  ; 设置控制寄存器CR0（即机器状态字），进入保护模式。
  mov ax, 0x0001        ; 在CR0中设置保护模式标志PE(位0)。
  lmsw ax               ; loads the machine status word (part of CR0) from the
                        ; source operand. This instruction can be used to switch
                        ; to Protected Mode; if so, it must be followed by an
                        ; intrasegment jump to flush the instruction queue.
  jmp 8:0               ; 跳转至段选择符值8指定的段中（即GDT表第2个段描述符），
                        ; 偏移0处。注意此时段值已是段选择符。该段的线性基地址是0

  ; 下面是全局描述符表GDT的内容。其中包含3个段描述符。第1个不用，另2个是代码和数
  ; 据段描述符。
gdt:
  ; 每个描述符占8个字节，也就是4个字
  dw 0, 0, 0, 0         ; 段描述符0，不用。每个描述符项占8字节。

  ; 第二个描述符
  dw 0x07FF             ; 段限长值=2047 (2048*4096=8MB)。
  dw 0x0000             ; 段基地址=0x00000。
  dw 0x9A00             ; 是代码段，可读/执行。
  dw 0x00C0             ; 段属性颗粒度=4KB，80386。

  ; 第三个描述符，与代码段重合，这就是传说中的“别名”技术
  dw 0x07FF             ; 段限长值=2047 (2048*4096=8MB)。
  dw 0x0000             ; 段基地址=0x00000。
  dw 0x9200             ; 是数据段，可读写。
  dw 0x00C0             ; 段属性颗粒度=4KB，80386

  ; 下面分别是LIDT和LGDT指令的6字节操作数。
idt_48:
  ; 将要赋值给IDT寄存器的6个字节，指明了中断描述符表的基址和限长
  dw 0x0000             ; IDT表长度是0。
  dw 0x0000, 0x0000     ; IDT表的线性基地址也是0。
  ; 在这里这个中断描述符表指向0x0000:0000处，长度也为0，不要奇怪，没有初始化
  ; 而已，占个位置先！:)
gdt_48:
  ; 将要赋值给GDT寄存器的6个字节，指明了全局描述符表的基址和限长
  dw 0x07FF             ; GDT表长度是2KB，可容纳256个描述符项。
  dw 0x7C00+gdt, 0x0000 ; GDT表的线性基地址在0x7c0段的偏移gdt处。

  times 510-($-$$) db 0 ; 填充不用的空间为0，凑够510个字节
  dw 0xAA55             ; 引导扇区有效标志。必须处于引导扇区最后2字节处。
