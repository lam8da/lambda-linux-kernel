; https://blog.csdn.net/huer0625/article/details/5396451
;名称：boot04.asm
;作用：把"Hello, the OS of world!"写在屏幕的第0行第0列并且当键盘发生输入时，
; 进入菜单选择画面后停止不动进入死循环。不过这次我并不想把这个程序代码写入
; 软盘的0面0道1扇区而是把它安装在0面0道2扇区以后,所以为了能够运行它。
; 首先，我需要写一段引导代码且把这段代码安装在软盘的软盘的0面0道1扇区。
; 呵呵，行动！
;
; 由于需要把这段代码写入软盘的0面0道1扇区（即0号逻辑扇区），
; 所以额外加了前面一段代码。
; 本程序均在windows 环境下调试并在dos虚拟机下写入软盘。
; 具体有关环境的搭建，需要我们可以交流。也建议再看下面
; 代码之前先把调试环境搭好。边看，边编译，边运行，边调试，边修改，边创新！
;   声明：
; 出于学术尊重，我会把我的代码以及想法的来源做个交代。凡是不
; 自己独立想出来的，我都会交代。但局限本人学识和时间的有限，所以我交代的
; 来源仅是给出我所参考的来源。并不意味我提供的来源就是第一作者。对于这个 
; 源码，任何人可以随意修改，任意传播。看注释，请挑对自己有用的看。觉得太简单的，可以立马逃过，
; 无需浪费时间。To try， not memorize!在计算机的领域里，我很欣赏这句话。
; 
;作者：hk0625
;开始编辑时间：2010年3月13号 星期六 11:30AM
;最后修改时间：2010年3月13号 星期三 03：30PM

;修改次数: 100次 
;地点：北京化工大学 郁夫图书馆文法阅览室小圆桌


assume cs:code
code segment
;这段代码的作用是把boot以下程序段写入软盘中代码调用bios的13H中断。具体设置可以查
;看有关bios具体的参考资料有:
;参考一：《IBM-PC汇编语言程序设计（第二版）》附录5 BIOS功能调用
;清华大学出版社 沈美明 温冬婵 编著
;参考二：《汇编语言》 第17章第4小节 清华大学出版社 王爽 著
start: mov ax, cs 
 mov es, ax
 mov bx, offset boot
  
 mov al, 4
 mov ch, 0 
 mov cl, 1 
 mov dl, 0
 mov dh, 0
 mov ah, 3
 int 13H 
 
 mov ax, 4c00H
 int 21H

;系统开机后，CPU自动进入到ffff:0单元处执行。在此处有一条跳转指令。cpu执行该指令
;后，转去执行BIOS中的硬件系统检测和初始化程序。硬件系统检测和初始化完成后，
;调用BIOS第19H号功能调用进行操作系统引导。（上述，摘自王爽编著《汇编原理》课程设计二）
;因为下面这段代码刚好是512字节且以0aa55H结尾，并且它被上一段程序写入0面0道1扇区。
;这里可能你会好奇，为什么这段程序代码会被加载在第一扇区？其实，这很简单。因为
;首先，我们是从下面开始把代码写入软盘的0面0道1扇区的。其次，一个扇区大小十多？
;刚好是512字节，而下面这段也刚好是512字节。所以它会被int 19H认为是引导程序
;进而被加载到内存07c00H处。
;这段代码的作用就是把其它扇区的代码加载到内存7e00处（这个位置是我假定的,
;如果你喜欢你完全可以加载到其他地方,不过要注意别加载到只读ROM去，那可不好了。呵呵，
;有关内存的分布的更多入门知识可以参考王爽著《汇编原理》第1章, 页数4~10。）在这里我
;假定其他段程序被写入0面0道2扇区及其以后的扇区。至于要调用的扇区数根据具体情况而定。
;在这个程序里假定3个吧，因为它们已经足够了。以后不够再加。呵呵， let's try!
;(let's try 是let us try!缩写。不知道能不能这样缩写，如果不能，那就创造它吧!)
;下面我调用BIOS第13H功能来具体实现它。

 org 7c00H ;这句话的作用和具体实现原理，我不太明白。
    ;先留下这个问题，以后在思考。
boot: mov ax, 0000
 mov es, ax
 mov bx, 7e00H
 mov al, 3
 mov ah, 2
 mov cl, 2
 mov ch, 0
 mov dl, 0
 mov dh, 0
 int 13H
 mov bx, offset os
 jmp dword ptr es:[bx];
 
os: dw 7e00H, 0000H 
 db 510 - ($ - offset boot) dup(0)
 dw 0aa55H

;作用：把"Hello, the OS of world!"写在屏幕的第0行第0列并且
; 当键盘发生输入时，重启计算机。
kaishi:
 mov ax, cs 
 mov ds, ax 
 mov es, ax 
 call DispStr 
;调用BIOS第16H号0号子功能，等待键盘输入。一旦有键盘输入，重启计算机。
;具体的原理可以参看王爽编著的《汇编语言》的课程设计二。
 mov ah, 0 
 int 16H 
disp: call clear ;清屏
 call DispMenu ;调用显示菜单子程序
 mov ah, 0
 int 16H
 cmp al , '1'
 jne next2
 call pro_reset
next2: cmp al, '2'
 jne next3
 call pro_start
next3: cmp al, '3'
 jne next4
 call pro_clock
; jmp disp
next4: cmp al, '4'
 jne disp
 call pro_set
 mov ah, 0
 int 16H  ;等待按键行为
 jmp disp  ;返回菜单
;子程序pro_reset的作用是重新启动计算机系统。相当于按下复位键。
pro_reset:
 push bx

 mov bx, offset reset
 jmp dword ptr cs:[bx]
 
 pop bx
 ret
reset:  dw 0, 0ffffH
;子程序pro_start的作用：从C盘启动现有的操作系统操作系统
pro_start:
 push ax
 push bx
 push cx
 push dx
 push es
 
 mov ax, 0
 mov es, ax
 mov bx, 7c00H
 mov ax, 0201H
 mov cx, 0001H
 mov dx, 0080H
 int 13H
 jmp bx

 pop es
 pop dx
 pop cx
 pop bx
 pop ax
 ret
;子程序pro_clock的作用是显示时间 年/月/日 时：分：秒
pro_clock:
 push ax
 push bx
 push cx
 push dx
 push si
 push di
 push es

 call clear
;不断循环知道按下(ESC)键
pro_while:
 mov ax, 0b800H
 mov es, ax
 mov di, 5*160+20*2
 
 mov  bx, 0
 mov si, offset time
 mov cx, 6
;从bios获得时间值并显示时间字符串 yy/mm/dd hh:mm:ss
pro_clock_s: 
 mov al, [si+bx]
 out 70H, al
 in al, 71H
 mov ah, al
 push cx
 mov cl, 4
 shr ah, cl
 pop cx
 and al, 0FH
 add ah, 30H
 add al, 30H
 mov byte ptr es:[di], ah
 mov byte ptr es:[di+2], al
 mov al, [si+bx+1]
 mov byte ptr es:[di+4], al
 add di, 6
 add bx, 2
 loop pro_clock_s

 in al, 60H  ;获得键盘扫描码，如果是ESC键则退回主菜单
 cmp al, 01H  
 je  pro_ret
;获得当前时间的秒数，为了跟下面的循环比较来判断时间是否过了一秒。
;在这里，有一个事实需要知道，那就是cpu执行速度非常快。一般的机子
;每秒钟估计可以执行上百万条指令。呵呵，明白了这个道理，这不难理解
;下面的算法了吧。
 mov al, 0
 out 70H, al
 in al, 71H
;判断时间是否过去一秒钟了，如果是则更新时间字符串
pro_second:
 mov bl, al
 in al, 60 ;获取键盘扫描码，如果是ESC键则退回主菜单
 cmp al, 01H
 je pro_ret
 mov al, 0
 out 70H, al
 in  al, 71H
 cmp al, bl
 jne pro_while
 jmp pro_second
 pro_ret: 
 pop es 
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 ret
time: db 9, '/', 8, '/', 7, ' ', 4, ':', 2, ':', 0, 0
;子程序pro_set的作用按一定格式输入时间，输完后按回车键修改bios的时间。
pro_set:
;显示时间输入格式
 call sub_set_disp
;显示当前输入的字符。
 call sub_set_input
;将上面得到的数据转化成相应的BCD码
 call sub_set_trans
;根据上面的BCD码进行BIOS时间设置
 call sub_set_set
 ret
;子程序：显示时间输入格式:yy/mm/dd hh:mm:ss（提示信息） 
sub_set_disp:
 push ax
 push bx
 push cx
 push dx
 push es
 push bp

 call clear
 mov ax, cs
 mov es, ax
 mov bp, offset sub_set_disp_string
 mov ax, 1300H
 mov bx, 000cH
 mov cx, 17
 mov dx, 0510H
 int 10H
 
 pop bp
 pop es
 pop dx
 pop cx
 pop bx
 pop ax
 ret
sub_set_disp_string: db "yy/mm/dd hh:mm:ss"
sub_set_input:
 push ax
 push bx
 push cx
 push dx
 push es
 push bp
 push di
 
 mov cx, 0
 mov dx, 0610H
 mov bh, 0
 mov ah, 02H
 int 10H

sub_set_input_s: 
 mov ah, 0
 int 16H
 cmp ah, 1cH  ;判断是否是回车键(ENTER)
 jz  sub_set_input_ret ;是，退出循环
 push ax  
 mov ax, cs
 mov es, ax
 mov bp, offset sub_set_input_data
 mov bx, cx
 add bx, bp
 mov di, es
 pop ax
 cmp ah, 0eH ;判断是否是退格键（BACKSPACE）
 jz sub_set_input_dec ;是，删除一个字符并重新显示
 mov [di+ bx], al
 inc cx
 jmp sub_set_input_show
sub_set_input_dec:
 cmp cx, 0
 jz set_input_jump
 dec cx
set_input_jump:
 call sub_set_disp ;调用sub_set_disp函数，清屏并重新输出提示信息。
sub_set_input_show:
 mov ax, 1300H
 mov bx, 000cH
 mov dx, 0610H
 int 10H
 mov ah, 02H
 mov bh, 00H
 add dl, cl
 int 10H
 jmp sub_set_input_s 

sub_set_input_ret:
 pop di
 pop bp
 pop es
 pop ax
 pop bx
 pop cx
 pop dx
 ret
sub_set_input_data: db 128 dup(0) 
sub_set_trans:
 push ax
 push bx
 push cx
 push si
 push bp
 push di
 
 mov ax, cs
 mov si, ax
 mov ax, cs
 mov di, ax
 mov bp, offset sub_set_trans_data
 mov bx, offset sub_set_input_data
 mov cx, 6
sub_set_trans_s:
 mov ax, [si+bx]
 sub ax, 3030H
 push cx
 mov cl, 4
 shl al, cl
 pop cx
 add ah, al
 mov [bp+di], ah
 add bx, 3
 inc bp
 loop sub_set_trans_s
 
 pop di
 pop bp
 pop es
 pop cx
 pop bx
 pop ax
 ret
sub_set_trans_data: db 6 dup(0)
sub_set_set:
 push ax
 push bx
 push cx
 push si
 push di
 
 mov ax, cs
 mov si, ax
 add si, offset sub_set_trans_data
 mov di, ax
 add di, offset sub_set_set_data
 mov cx, 6
 mov bx, 0
sub_set_set_s:
 mov al, [di+bx]
 out 70H, al
 mov al, [si+bx]
 out 71H, al
 inc bx
 loop sub_set_set_s

 pop di
 pop si
 pop cx
 pop bx
 pop ax
 ret
sub_set_set_data: db 9, 8, 7, 4, 2, 0
;这段代码我是改写于渊的《自己动手编写操作系统》。要搞懂的这段代码的意思，
;只需要把BIOS中第10H号功能调搞懂。
DispStr:
 push ax
 push bx
 push cx
 push dx
 push bp

 mov ax, offset Message 
 mov bp, ax
 mov cx, 23 
 mov ax, 1301H 
 mov bx, 000cH  
 mov dl, 0 
 int 10H

 pop bp
 pop dx
 pop cx
 pop bx
 pop ax
 ret
Message: db "Hello, the OS of world!"

;作用：显示菜单 
;   1) reset pc
;   2) start system
;   3) clock
;   4) set clock
;在编写操作系统前，我想把王爽老师的课程设计二完成，作为自己汇编语言的结业考试
;以下有关直接直接定址表的技巧参见王爽老师编著《汇编原理》第16.7-p284
DispMenu: jmp short show
Menu   dw Menu1, Menu2, Menu3, Menu4
Menu1  db "1) reset pc"
Menu2  db "2) start system"
Menu3 db "3) clock"
Menu4 db "4) set clock"
leng dw 11, 15, 8, 12

show: push ax
 push bx
 push cx
 push dx
 push si
 push es
 push bp
 
 call clear
 mov ax, cs
 mov es, ax
 mov si, 0
 mov cx, 4
 mov dh, 10
Menu_s: 
 mov bp, Menu[si]
 mov dl, 20
 mov ax, 1301H
 mov bx, 000cH
 push cx
 mov cx, leng[si]
 int 10H
 add si, 2
 inc dh
 pop cx
 loop Menu_s

 pop bp
 pop es
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 ret
;清屏子程序：把整个屏幕清空。呵呵
clear:
 push ax
 push bx
 push cx
 push es

 mov ax, 0b800H
 mov es, ax
 mov bx, 0
 mov ax, 0700H
 mov cx, 4000H
clear_s:
 mov es:[bx], ax
 add bx, 2
 loop clear_s

 pop es
 pop cx
 pop bx
 pop ax
 ret

code ends
end start
