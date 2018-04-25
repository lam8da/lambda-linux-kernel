; 说明：
; 1. 这是实现多任务内核程序，包含32位保护模式初始化设置代码、时钟中断代码、系统
;    调用中断代码和两个任务的代码。
; 2. 这段程序被引导扇区代码读取到物理地址0x10000H处然后又移动到物理地址0x00000，
;    他被编译后写在第2个扇区开始的地方，在这里写代码就不用顾忌512字节的限制了，
;    随便写几个扇区
; 3. 从这时候开始已经是在保护模式下了。
; 4. 在进入保护模式后，程序重新建立和设置IDT、GDT表的主要原因是为了让程序在结构
;    上比较清晰，也为了与后面Linux 0.12内核源代码中这两个表的设置方式保持一致。
;    当然，就本程序来说我们完全可以直接使用boot.asm中设置的IDT和GDT表位置，填入
;    适当的描述符项即可。
; 5. 在初始化完成之后程序移动到任务0开始执行，并在时钟中断控制下进行任务0和1之间
;    的切换操作。
; 6. nasm的语法在：http://www.cburch.com/csbsju/cs/350/docs/nasm/nasmdoc0.html

LATCH    equ 11930  ; 定时器初始计数值，即每隔10ms发送一次中断请求。
CS_SEL   equ 0x08   ; gdt的第二个段即代码段选择符
DS_SEL   equ 0x10   ; gdt的第三个段即数据段选择符，和代码段重合。
SCRN_SEL equ 0x18   ; 屏幕显示内存段选择符。
TSS0_SEL equ 0x20   ; 任务0的TSS段选择符。
LDT0_SEL equ 0x28   ; 任务0的LDT段选择符。
TSS1_SEL equ 0x30   ; 任务1的TSS段选择符。
LDT1_SEL equ 0x38   ; 任务1的LDT段选择符。

; 全局描述符表在引导扇区的实现中只有三项，第一项当然是空选择符，第二项是基址为
; 0x00000、长度为8M的代码段，第三项是基址为0x00000、长度为8M的数据段，也就是别名
; 技术的代码段
; 而在这里的代码中重新设置了全局描述符表，里面留了两个TSS和LDT的位置，现在这里的
; TSS0_SEL就将要指向新的全局描述符表中的偏移位置为0x20也就是第4个描述符
; 同样地，LDT0_SEL指向了第5个描述符，随后就是TSS1和LDT1了

  ; 让NASM生成32位的cpu指令
  [BITS 32]
startup_32:
  ; 首先加载数据段寄存器DS、堆栈段寄存器SS和堆栈指针ESP。所有段的线性基地址都是0
  mov eax, DS_SEL
  mov ds, ax
  lss esp, [init_stack]  ; 指令"lss reg32, mem"把在mem中的32位偏移量和16位段选择
                         ; 符分别加载到reg32和ss中。于是这里表示：
                         ; 1. esp=[init_stack]=init_stack（见下面init_stack处的
                         ;    第一个双字的内容）
                         ; 2. ss=[init_stack+32]=DS_SEL

  ; 在新的位置重新设置IDT和GDT表。
  call setup_idt
  call setup_gdt

  ; 在改变了GDT之后重新加载所有段寄存器。
  mov eax, 0x10
  mov ds, eax
  mov es, eax
  mov fs, eax
  mov gs, eax
  lss esp, [init_stack]

  ; 设置8253定时芯片。把计数器通道0设置成每隔10ms向中断控制器发送一个中断请求信号。
  mov al, 0x36     ; 控制字：设置通道0工作在方式3、计数初值采用二进制。
  mov edx, 0x43        ; 8253芯片控制字寄存器写端口
  out dx, al

  mov eax, LATCH       ; 初始计数值设置为LATCH(1193180/100)，即频率100Hz。
  mov edx, 0x40        ; 通道0的端口
  out dx, al       ; 分两次把初始计数值写入通道0

  mov al, ah
  out dx, al

  ; 在IDT表第8和第128（0x80）项处分别设置定时中断门描述符和系统调用陷阱门描述符。
  mov eax, 0x00080000  ; 中断程序属内核，即EAX高字是内核代码段选择符

  mov ax, timer_interrupt  ; 设置定时中断门描述符。取定时中断处理程序地址。
  mov dx, 0x8e00       ; 中断门类型是14（屏蔽中断），特权级0或硬件使用。
  mov ecx, 0x08        ; 开机时BIOS设置的时钟中断向量号8.这里直接使用它。
  lea esi, [idt+ecx*8]
  mov [esi], eax
  mov [esi+4], edx

  mov ax, system_interrupt ; 设置系统调用陷阱门描述符。取系统调用处理程序地址。
  mov dx, 0xef00       ; 陷阱门类型是15，特权级3的程序可执行
  mov ecx, 0x80        ; 系统调用向量号是0x80
  lea esi, [idt+ecx*8] ; 把IDT描述符项0x80地址放入esi中，然后设置该描述符
  mov [esi], eax
  mov [esi+4], edx


  push edx
  push ds
  push eax
  mov edx, 0x10        ; 首先让DS指向内核数据段
  mov ds, dx
  mov eax,'W'
  call write_char     ; 然后调用显示字符子程序write_char，显示AL中的字符。
  pop eax
  pop ds
  pop edx



  ; 好了，现在我们为移动到任务0（任务A）中执行来操作堆栈内容，在堆栈中人工建立中断返回时的场景。
  pushf           ; 复位标志寄存器EFLAGS中的嵌套任务标志
  and dword [esp], 0xffffbfff
  popf

  mov eax, TSS0_SEL    ; 把任务0的TSS段选择符加载到任务寄存器TR
  ltr ax

  mov eax, LDT0_SEL    ; 把任务0的LDT段选择符加载到局部描述符表寄存器LDTR
  lldt ax         ; TR和LDTR只需人工加载一次，以后CPU会自动处理。

  mov dword [current], 0   ; 把当前任务号0保存在current变量中

  sti         ; 现在开启中断，并在栈中营造中断返回时的场景。

  ; 假装是从中断程序返回，从而实现从特权级0的内核代码切换到特权级3的用户代码中去
  push 0x17       ; 把任务0当前局部空间数据段（堆栈段）选择符入栈。
  push krn_stk0           ; 把堆栈指针入栈（也可以直接把esp入栈）。
  pushf           ; 把标志寄存器入栈。
  push 0x0f       ; 把当前局部空间代码段选择符入栈。
  push task0      ; 把代码指针入栈

  iret            ; 执行中断返回指令，从而切换到特权级3的任务0中执行。

; ==============================================================================
; 设置GDT的子程序。
setup_gdt:
  ; 使用在内存区域lgdt_opcode中的6字节操作数设置GDT表位置和长度。
  lgdt [lgdt_opcode]
  ret

; ==============================================================================
; 这段代码暂时设置IDT表中所有256个中断门描述符都为同一个默认值，均使用默认的中断
; 处理过程ignore_int。设置的具体方法是：首先在eax和edx寄存器对中分别设置好默认中
; 断门描述符的0～3字节和4～7字节的内容，然后利用该寄存器对循环往IDT表中填充默认
; 中断门描述符内容。
setup_idt:
  lea edx, [ignore_int]  ; 取ignore_int的物理地址
  mov eax, 0x00080000    ; 选择符为0x0008。
  mov ax, dx
  ; EAX寄存器中高16位存放了下面要用到的段选择子0x0008,也就是指向GDT中的第1个代码段描述符,
  ; 基址为0x10000,限长为8M
  ; EAX寄存器中低16位存放了下面要用到的偏移地址 ignore_int 。
  mov dx, 0x8e00       ; 这里是下面要用到的属性字节，0x8E00的意思是"有效的386中断门,特权级为0"。
  lea edi, [idt]
  mov ecx, 256     ; 循环设置所有256个门描述符
  rp_idt:
  ; 中断描述符表中的每一个描述符的格式是:
  ; 1、每个描述符占8个字节；
  ; 2、第0、1个字节是偏移地址的低16位；
  ; 3、第2、3个字节是段选择子；
  ; 4、第4、5个字节是属性字节；
  ; 5、第6、7个字节是偏移地址的高16位。
  mov [edi], eax
  mov [edi+4], edx
  add edi, 8
  dec ecx
  jne rp_idt
  lidt [lidt_opcode]  ; 最后用6字节操作数加载IDTR寄存器。
  ret
; =======================================================================================
; 显示字符子程序。取当前光标位置并把AL中的字符显示在屏幕上。整屏可显示80×25个字符。
write_char:
  push gs         ; 首先保存要用到的寄存器，EAX由调用者负责保存。
  push ebx

  mov ebx, SCRN_SEL    ; 然后让GS指向显示内存段（0xb8000）。
  mov gs, ebx

  mov ebx, [scr_loc]   ; 再从变量scr_loc中取目前字符显示位置值。
  shl ebx, 1       ; 因为在屏幕上每个字符还有一个属性字节，因此字符
              ; 实际显示位置对应的显示内存偏移地址要乘以2
  mov [gs:ebx], al
  shr ebx, 1       ; 把字符放到显示内存后把位置值除2加1，此时位置值对
  inc ebx         ; 应下一个显示位置。如果该位置大于2000，则复位成
  cmp ebx, 2000        ; 0
  jb x1
  mov ebx, 0

  x1:
  mov [scr_loc], ebx   ; 最后把这个位置值保存起来（scr_loc），

  pop ebx         ; 并弹出保存的寄存器内容，返回。
  pop gs
  ret
; =======================================================================================
; 以下是3个中断处理程序：默认中断、定时中断和系统调用中断。
align 4             ; 双字对齐
ignore_int:         ; ignore_int是默认的中断处理程序，若系统产生了其他中断，则会在屏幕上显示一个字符“C”。
  push ds
  push eax

  mov eax, 0x10        ; 首先让DS指向内核数据段，因为中断程序属于内核。
  mov ds, eax

  mov eax, 67      ; 在AL中存放"C"的代码，调用显示程序显示在屏幕上
  call write_char

  pop eax
  pop ds
  iret
; ---------------------------------------------------------------------------------------
; 这是定时中断处理程序。其中主要执行任务切换操作。
align 4             ; 双字对齐
timer_interrupt:
  push ds
  push eax

  mov eax, 0x10        ; 首先让DS指向内核数据段
  mov ds, ax

  mov al, 0x20     ; 然后立刻允许其他硬件中断，即向8259A发送EOI命令
  out 0x20, al

  mov eax, 1       ; 接着判断当前任务，若是任务1则去执行任务0，或反之
  cmp dword [current], eax

  je x2
  mov dword [current], eax ; 若当前任务是0，则把1存入current，并跳转到任务1
  jmp TSS1_SEL:0      ; 去执行。注意跳转的偏移值无用，但需要写上。

  jmp x3

  x2:
  mov dword [current], 0   ; 若当前任务是1，则把0存入current，并跳转到任务0
  jmp TSS0_SEL:0      ; 去执行

  x3:
  pop eax
  pop ds

  iret
; ---------------------------------------------------------------------------------------
; 系统调用中断int 0x80处理程序。该示例只有一个显示字符功能。
align 4             ; 双字对齐
system_interrupt:
  push ds
  push edx
  push ecx
  push ebx
  push eax

  mov edx, 0x10        ; 首先让DS指向内核数据段
  mov ds, dx
  call write_char     ; 然后调用显示字符子程序write_char，显示AL中的字符。

  pop eax
  pop ebx
  pop ecx
  pop edx
  pop ds
  iret

; =======================================================================================
current:
  dd 0        ; 当前任务号（0或1）。
scr_loc:
  dd 0        ; 屏幕当前显示位置。按从左上角到右下角顺序显示。

align 4
lidt_opcode:    ; 这里定义的6个字节是给 IDT寄存器 用的,使用的指令是 lidt lidt_opcode
  dw 256*8-1      ; 加载IDTR寄存器的6字节操作数：表长度和基地址。
  dd idt

lgdt_opcode:
  dw (end_gdt-gdt-1)  ; 加载GDTR寄存器的6字节操作数：表长度和基地址
  dd gdt

align 8
idt:    ; IDT空间。共256个门描述符，每个8字节，占用2KB。
  times 256 dd 0          ; dd=double data word 双字也就是4字节
  times 256 dd 0

gdt:
  dw 0x0000, 0x0000, 0x0000, 0x0000  ; 空选择子。为啥要搞个空的在这里？
  dw 0x07FF, 0x0000, 0x9A00, 0x00C0  ; 基址0x00000限长(0x7ff+1)*4KB=8M的代码段，
                                     ; 选择符0x08
  dw 0x07FF, 0x0000, 0x9200, 0x00C0  ; 基址0x00000限长8M的数据段，选择符0x10
  dw 0x0002, 0x8000, 0x920B, 0x00C0  ; 基址0xB8000限长12K的显存数据段，选择符0x18
  dw 0x0068, tss0,   0xE900, 0x0000  ; 对应于TSS0的描述符，基址暂定0x00000，但会
                                     ; 被设置为指向tss0处，限长为0x68，即102个
                                     ; 字节，其选择符是0x20。
  dw 0x0040, ldt0,   0xE200, 0x0000  ; 对应于LDT0的描述符，基址暂定0x00000，但会
                                     ; 被设置为指向ldt0处，限长为0x40，即64个字
                                     ; 节，其选择符是0x28。
  dw 0x0068, tss1,   0xE900, 0x0000  ; 对应于TSS1的描述符，基址暂定0x00000，但会
                                     ; 被设置为指向tss1处，限长为0x68，即102个
                                     ; 字节，其选择符是0x30。
  dw 0x0040, ldt1,   0xE200, 0x0000  ; 对应于LDT1的描述符，基址暂定0x00000，但会
                                     ; 被设置为指向ldt1处，限长为0x40，即64个字
                                     ; 节，其选择符是0x38。
end_gdt:

  times 128 dd 0  ; 初始内核堆栈空间。
init_stack:       ; 刚进入保护模式时用于加载SS:ESP堆栈指针值。
  dd init_stack   ; 堆栈段偏移位置。
  dw DS_SEL       ; 堆栈段==数据段。

  ; 下面是任务0的LDT表段中的局部段描述符。
align 8
ldt0:
  dw 0x0000, 0x0000, 0x0000, 0x0000; 第1个描述符，不用。
  dw 0x03FF, 0x0000, 0xFA00, 0x00C0; 基址为0x00000、限长为4M字节、DPL为3的代码段、对应的选择符是0x08
  dw 0x03FF, 0x0000, 0xF200, 0x00C0; 基址为0x00000、限长为4M字节、DPL为3的数据段、对应的选择符是0x10

  ; 下面是任务0的TSS段的内容。注意其中标号等字段在任务切换时不会改变。
tss0:
  dd 0                        ; back link
  dd krn_stk0, 0x10               ; esp0, ss0
  dd 0, 0, 0, 0, 0                    ; esp1, ss1, esp2, ss2, cr3
  dd task0                    ; 确保第一次切换到任务0的时候EIP从这里取值,所以就从 task0 处开始运行,
                          ; 因为任务0的基址为 0x00000,和核心一样,不指定这个的话,
                          ; 第一次切换进来就会跑去执行 0x00000处的核心代码了,
                          ; 除非ldt0中的代码段描述符中的基址改成 task0 处的线性地址,
                          ; 那这里就可以设为0.
  dd 0x200                    ; EFLAGS的IF标志位为1，使得中断开放
  dd 0, 0, 0                    ; eax, ecx, edx
  dd 0, 0, 0, 0, 0                    ; ebx esp, ebp, esi, edi
  dd 0x17, 0x0f, 0x17, 0x17, 0x17, 0x17        ; es, cs, ss, ds, fs, gs
  dd LDT0_SEL, 0x08000000  ; ldt，trace bitmap

  times 128 dd 0      ; 任务0的内核栈空间

krn_stk0:

  ; 下面是任务1的LDT表段内容和TSS段内容。
ldt1:
  dw 0x0000, 0x0000, 0x0000, 0x0000; 第1个描述符，不用。
  dw 0x03FF, 0x0000, 0xFA00, 0x00C0
  dw 0x03FF, 0x0000, 0xF200, 0x00C0
tss1:
  dd 0            ; back link
  dd krn_stk1, 0x10   ; esp0, ss0
  dd 0, 0, 0, 0, 0                    ; esp1, ss1, esp2, ss2, cr3
  dd task1                    ; 确保第一次切换到任务0的时候EIP从这里取值,所以就从 task0 处开始运行,
                          ; 因为任务0的基址为 0x00000,和核心一样,不指定这个的话,
                          ; 第一次切换进来就会跑去执行 0x00000处的核心代码了,
                          ; 除非ldt0中的代码段描述符中的基址改成 task0 处的线性地址,
                          ; 那这里就可以设为0.
  dd 0x200                    ; EFLAGS的IF标志位为1，使得中断开放
  dd 0, 0, 0                    ; eax, ecx, edx
  dd 0, 0, 0, 0, 0                    ; ebx esp, ebp, esi, edi
  dd 0x17, 0x0f, 0x17, 0x17, 0x17, 0x17        ; es, cs, ss, ds, fs, gs
  dd LDT1_SEL, 0x08000000              ; ldt，trace bitmap

  times 128 dd 0      ; 任务1的n内核栈空间
krn_stk1:


  ; 下面是任务0和任务1的程序，它们分别循环显示字符“A”和“B”。
task0:
  mov eax, 0x17        ; 首先让DS指向任务的局部数据段
  mov ds, ax       ; 因为任务没有使用局部数据，所以这两句可省略
  mov al, 65       ; 把需要显示的字符"A"放入AL寄存器中
  int 0x80        ; 执行系统调用，显示字符
  mov ecx, 0xfff       ; 执行循环，起延时作用
  y1:
  loop y1

  jmp task0       ; 跳转到任务代码开始处继续显示字符

task1:
  mov al, 66       ; 把需要显示的字符"B"放入AL寄存器中
  int 0x80        ; 执行系统调用，显示字符
  mov ecx, 0xfff       ; 延时一段时间，并跳转到开始处循环显示
  y2:
  loop y2

  jmp task1


  times 128 dd 0      ; 这是任务1的用户栈空间
usr_stk1:
