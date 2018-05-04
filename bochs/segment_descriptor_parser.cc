#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 定义描述符中的低32位
union DescriptorLowDWord {
  struct {  // Code/data segment
    unsigned short limit_0_15 : 16;  // 段限长0-15位
    unsigned short base_0_15 : 16;   // 基地址0-15位
  };
  struct {  // Gate
    unsigned short offset_0_15_or_reserved : 16;
    unsigned short selector : 16;
  };
};

// 定义描述符中的高32位(通用格式)
struct DescriptorHighDWord {
  // 1st byte
  union {
    struct {  // Code/data segment
      unsigned char base_16_23 : 8;   // 基地址16-23位
    };
    struct {  // Gate
      unsigned char param_count_or_reserved : 5;
      unsigned char zeros_or_reserved : 3;
    };
  };
  // 2nd byte
  unsigned char type : 4;         // 段类型
  unsigned char s : 1;            // 描述符类型，0是系统描述符，1是代码或数据
  unsigned char dpl : 2;          // 特权级
  unsigned char p : 1;            // 段是否存在于内存中
  // 3th and 4th byte
  union {
    struct {  // Code/data segment
      unsigned char limit_16_19 : 4;  // 段限长16-19位
      unsigned char avl : 1;          // 无预定义功能，可由操作系统任意使用
      unsigned char l : 1;            // 保留给64位处理器使用
      unsigned char d_b : 1;          // 1/0表示代码/数据/堆栈段运行于32/16位模式
      unsigned char g : 1;            // 段限长的比例因子，0/1表示以1/4KB位单位
      unsigned char base_24_31 : 8;   // 基地址24-32位
    };
    unsigned short offset_16_31_or_reserved : 16;
  };
};

struct Descriptor {
  union DescriptorLowDWord l_dw;
  struct DescriptorHighDWord h_dw;
};

int TypeBit(Descriptor d, int bit) {
  return (d.h_dw.type & (1 << bit)) >> bit;
}

int ToBinary(int decimal) {
  int b = 0;
  unsigned int mask = (1 << 31);
  while (mask) {
    b = b * 10 + ((decimal & mask) ? 1 : 0);
    mask >>= 1;
  }
  return b;
}

void Print_P_DPL_S_TYPE(Descriptor d) {
  printf("- segment %s in memory (P=%d)\n",
         (d.h_dw.p ? "presents" : "doesn't present"), d.h_dw.p);
  printf("- descriptor privilege level (DPL, 0 is the most): %d\n", d.h_dw.dpl);
  printf("- descriptor type: %s segment (S=%d)\n",
         d.h_dw.s ? "non-system (code or data)" : "system", d.h_dw.s);
  printf("- type 0x%x: ", d.h_dw.type);
}

/*
if (system == 0) {  // 系统段
  printf("系统段描述符\n");
  if (type == 9 || type == 11 || type == 2) {
    printf("基地址 = %#x\n", seg_base);
    printf("段限长 = %#x ，", seg_limit);
    if (ph->g == 1) {
      printf("以4KB为单位\n");
    } else {
      printf("以B为单位\n");
    }
  }
  if (type == 9) {
    printf("TSS段，不忙\n");
  } else if (type == 11) {
    printf("TSS段，忙\n");
  } else if (type == 5) {
    printf("任务门，TSS段选择子 = %#x\n", pl->base_0_15);
  } else if (type == 6) {
    printf("调用门，段选择子 = %#x，偏移 = %#x , 参数个数 = %d\n",
           pl->base_0_15, offset, hig_dw & 0x1F);
  } else if (type == 2) {
    printf("LDT描述符\n");
  }
}
*/

unsigned int SegmentBase(Descriptor d) {
  return ((d.h_dw.base_24_31 << 24) | (d.h_dw.base_16_23 << 16) |
          d.l_dw.base_0_15);
}

// The processor puts together the two segment limit fields to form a 20-bit
// value. The processor interprets the segment limit in one of two ways,
// depending on the setting of the G (granularity) flag:
//
// - If the granularity flag is clear, the actual segment limit can range from 1
//   byte to 1 MByte, in byte increments. Note: 
//
//   segment limit 0      <=> actual segment limit 0
//   segment limit 1      <=> actual segment limit 1
//   ...
//   segment limit 2^20-1 <=> actual segment limit 1048975
//
// - If the granularity flag is set, the actual segment limit can range from 4
//   KBytes to 4 GBytes, in 4-KByte increments. Note:
//
//   segment limit 0      <=> actual segment limit 4KB-1
//   segment limit 1      <=> actual segment limit 8KB-1
//   ...
//   segment limit 2^20-1 <=> actual segment limit 4GB-1
//
// The processor uses the segment limit in two different ways, depending on
// whether the segment is an expand-up or an expand-down segment.
// - For expand-up segments, the offset in a logical address can range from 0 to
//   the segment limit. Offsets greater than the segment limit generate
//   general-protection exceptions (#GP, for all segment other than SS)
//   or stack-fault exceptions (#SS for the SS segment).
// - For expand-down segments, the segment limit has the reverse function; the
//   offset can range from the segment limit plus 1 to FFFFFFFFH or FFFFH,
//   depending on the setting of the B flag. Offsets less than or equal to the
//   segment limit generate general-protection exceptions or stack-fault
//   exceptions. Decreasing the value in the segment limit field for an
//   expanddown segment allocates new memory at the bottom of the segment's
//   address space, rather than at the top.
//   Q: what about an expand-down code segment?
//   Q: what about an expand-down segment with B=0 but G=1?
unsigned int SegmentLimit(Descriptor d) {
  return ((((d.h_dw.limit_16_19 << 16) | d.l_dw.limit_0_15) + 1)
          << (d.h_dw.g ? 12 : 0)) -
         1;
}

void PrintDescriptorName(const char* name) {
  const int len = 87;
  int dash_len = len - strlen(name);
  int left_dash_len = (dash_len >> 1) - 1;
  int right_dash_len = dash_len - left_dash_len - 2;
  for (int i = 0; i < left_dash_len; ++i) printf("=");
  printf(" %s ", name);
  for (int i = 0; i < right_dash_len; ++i) printf("=");
  printf("\n");
}

void HandleReserved(Descriptor d) {
  PrintDescriptorName("Reserved (not a valid descriptor)");
}

void HandleTSS(Descriptor d) {
  PrintDescriptorName("Task-state segment (TSS) descriptor");
}

void HandleLDT(Descriptor d) {
  PrintDescriptorName("Local descriptor-table (LDT) segment descriptor");
}

const char *kGateFormat =
"\n"
" 31                           16         11    8 7             0\n"
"+-------------------------------+-+---+-+-------+---------------+\n"
"|                               | |   | | TYPE  |     %s         |\n"
"|         %s         |P|DPL|S|-------|%s|\n"
"|                               | |   | |%s|     %s         |\n"
"+-------------------------------+-+---+-+-------+---------------+ 4\n"
"             0x%04x              %d %02d  %d %d %d %d %d  %03d    %05d\n"
"+-------------------------------+-------------------------------+\n"
"|                               |                               |\n"
"|     %s Segment Selector     |          %s         |\n"
"|                               |                               |\n"
"+-------------------------------+-------------------------------+ 0\n"
"             0x%04x                           0x%04x\n";

void HandleGate(Descriptor d) {
  int type = d.h_dw.type;
  switch (type) {
    case 4: case 5: case 6: case 7: case 12: case 14: case 15:
      break;
    default:
      printf("Invalid gate type: %d\n", type);
      return;
  }
  int gate_type = (d.h_dw.type & 0x7);
  int is_call_gate = (gate_type == 4);
  int is_task_gate = (gate_type == 5);
  int is_interrupt_gate = (gate_type == 6);
  int is_trap_gate = (gate_type == 7);

  int type_0x8 = TypeBit(d, 3);
  int type_0x4 = TypeBit(d, 2);
  int type_0x2 = TypeBit(d, 1);
  int type_0x1 = TypeBit(d, 0);
  int p = d.h_dw.p;
  int dpl = d.h_dw.dpl;
  int s = d.h_dw.s;

  const char* gate_type_str[4] = {"Call", "Task", "Interrupt", "Trap"};
  char gate_str[30];
  strcpy(gate_str, gate_type_str[gate_type-4]);
  strcat(gate_str, "-gate descriptor");
  PrintDescriptorName(gate_str);

  printf("- %s segment selector: 0x%04x\n", (is_task_gate ? "tss" : "code"),
         d.l_dw.selector);
  if (!is_task_gate) {
    int offset = ((((int)d.h_dw.offset_16_31_or_reserved) << 16) |
                  (d.l_dw.offset_0_15_or_reserved & 0x0000ffff));
    printf("- offset in segment: 0x%08x\n", offset);
  }

  // P, DPL, S, Type
  Print_P_DPL_S_TYPE(d);
  if (is_interrupt_gate || is_trap_gate) {
    printf("%dbit size gate (D=%d)\n", type_0x8 ? 32 : 16, type_0x8);
  } else {
    printf("\n");
  }

  // Parameter count
  if (is_call_gate) {
    printf("- parameter count: %d\n", d.h_dw.param_count_or_reserved);
  }

  printf(kGateFormat,
         is_task_gate ? " " : "|",
         is_task_gate ? "   Reserved  " : "Offset 31..16",
         is_task_gate ? "   Reserved    "
                      : (is_call_gate ? "0 0 0| #params " : "0 0 0| Reserved"),
         (is_call_gate || is_task_gate) ? "       " : "D      ",
         is_task_gate ? " " : "|",
         d.h_dw.offset_16_31_or_reserved,
         p, ToBinary(dpl), s, type_0x8, type_0x4, type_0x2, type_0x1,
         ToBinary(d.h_dw.zeros_or_reserved),
         ToBinary(d.h_dw.param_count_or_reserved),
         is_task_gate ? " TSS" : "Code",
         is_task_gate ? "  Reserved  " : "Offset 15..0",
         d.l_dw.selector, d.l_dw.offset_0_15_or_reserved);
}

// Reference:
// - https://blog.csdn.net/longintchar/article/details/78881396
// - "Figure 5-1. Descriptor Fields Used for Protection" of 
//   Intel® 64 and IA-32 Arcitectures Software Developer's Manual 3A
const char *kSegmentFormat =
"\n"
" 31           24         19   16         11    8 7             0\n"
"+---------------+-+-+-+-+-------+-+---+-+-------+---------------+\n"
"|  Base Address | | | |A| Limit | |   | | TYPE  |  Base Address |\n"
"|     31..24    |G|%s|L|V|19..16 |P|DPL|S|-------|    23..16     |\n"
"|               | | | |L|       | |   | |  %s|               |\n"
"+---------------+-+-+-+-+-------+-+---+-+-------+---------------+ 4\n"
"    %08d     %d %d %d %d  %04d   %d %02d  %d %d %d %d %d    %08d\n"
"+-------------------------------+-------------------------------+\n"
"|         Base Address          |         Segment Limit         |\n"
"|             15..0             |             15..0             |\n"
"|                               |                               |\n"
"+-------------------------------+-------------------------------+ 0\n"
"             0x%04x                          0x%04x\n";

void HandleCodeOrDataSegment(Descriptor d) {
  int is_code = TypeBit(d, 3);
  int type_0x4 = TypeBit(d, 2);
  int type_0x2 = TypeBit(d, 1);
  int type_0x1 = TypeBit(d, 0);
  int g = d.h_dw.g;
  int d_b = d.h_dw.d_b;
  int p = d.h_dw.p;
  int dpl = d.h_dw.dpl;
  int s = d.h_dw.s;
  int limit = SegmentLimit(d);
  unsigned int expand_down_data_seg_upper_bound = d_b ? 0xffffffff : 0x0000ffff;

  PrintDescriptorName(
      is_code ? "Code-segment descriptor" : "Data-segment descriptor");

  // Base, Limit, G
  printf("- segment base address: 0x%08x\n", SegmentBase(d));
  printf("- segment limit: 0x%08x", limit);
  if (g) printf("=%dK-1", (limit+1) >> 10);
  if (is_code || type_0x4 == 0) {
    // Expand up.
    printf(", range is [0x%08x, 0x%08x] (expand-up)\n", 0, limit);
  } else {
    printf(", range is [0x%08x, 0x%08x]",
           limit+1, expand_down_data_seg_upper_bound);
    if (expand_down_data_seg_upper_bound > (unsigned int)limit) {
      printf("=%uB", expand_down_data_seg_upper_bound - limit);
    } else {
      printf("=%dB", expand_down_data_seg_upper_bound - limit);
    }
    printf(" (expand-down)\n");
  }
  printf("- granularity: %s (G=%d)\n", (g ? "4KB" : "1B"), g);

  // B/D field
  if (is_code) {
    printf("- default length for effective addresses and operands: "
           "%d-bit addresses and %d-bit or 8-bit operands (D=%d)\n",
           (d_b ? 32 : 16), (d_b ? 32 : 16), d_b);
  } else {
    printf("- stack segment only: use %s (B=%d)\n",
           (d_b ? "32bit esp" : "16bit sp"), d_b);
    if (type_0x4) {
      printf("- expand-down data segment only: upper bound of the segment is "
             "%s (B=%d)\n",
             (d_b ? "0xffffffff" : "0xffff"), d_b);
    }
  }

  // P, DPL, S, Type
  Print_P_DPL_S_TYPE(d);
  printf("%s segment (TYPE & 0x08=%d), ", is_code ? "code" : "data", is_code);
  if (is_code) {
    //  Note:
    //  - A transfer of execution into a more-privileged conforming segment
    //    allows execution to continue at the current privilege level
    //  - A transfer into a nonconforming segment at a different privilege level
    //    results in a general-protection exception (#GP), unless a call gate or
    //    task gate is used
    printf("%s (C=%d), ", type_0x4 ? "conforming" : "nonconforming", type_0x4);
    printf("%s (R=%d), ", type_0x2 ? "execute/read" : "execute-only", type_0x2);
  } else {
    printf("%s (E=%d), ", type_0x4 ? "expand-down" : "expand-up", type_0x4);
    printf("%s (W=%d), ", type_0x2 ? "read/write" : "read-only", type_0x2);
  }
  printf("%s (A=%d)\n", type_0x1 ? "accessed before" : "not-accessed before",
         type_0x1);

  // Virtualize the format
  printf(kSegmentFormat, (is_code ? "D" : "B"), (is_code ? "C R A" : "E W A"),
         ToBinary(d.h_dw.base_24_31), g, d_b, d.h_dw.l, d.h_dw.avl,
         ToBinary(d.h_dw.limit_16_19), p, ToBinary(dpl), s,
         is_code, type_0x4, type_0x2, type_0x1, ToBinary(d.h_dw.base_16_23),
         d.l_dw.base_0_15, d.l_dw.limit_0_15);
}

void Parse(Descriptor d) {
  if (d.h_dw.s == 0) {
    // Table 3-2. System-Segment and Gate-Descriptor Types
    // (from Intel® 64 and IA-32 Arcitectures Software Developer's Manual 3A)
    //
    // Note: TSS = Task-state segment
    //
    // +-------------------+-------------------------+
    // |     Type Field    |       Description       |
    // | Decimal 11 10 9 8 |       32-Bit Mode       |
    // +-------------------+-------------------------+
    // | 0        0  0 0 0 | Reserved                |
    // | 1        0  0 0 1 | 16-bit TSS (Available)  |
    // | 2        0  0 1 0 | LDT                     |
    // | 3        0  0 1 1 | 16-bit TSS (Busy)       |
    // | 4        0  1 0 0 | 16-bit Call Gate        |
    // | 5        0  1 0 1 | Task Gate               |
    // | 6        0  1 1 0 | 16-bit Interrupt Gate   |
    // | 7        0  1 1 1 | 16-bit Trap Gate        |
    // | 8        1  0 0 0 | Reserved                |
    // | 9        1  0 0 1 | 32-bit TSS (Available)  |
    // | 10       1  0 1 0 | Reserved                |
    // | 11       1  0 1 1 | 32-bit TSS (Busy)       |
    // | 12       1  1 0 0 | 32-bit Call Gate        |
    // | 13       1  1 0 1 | Reserved                |
    // | 14       1  1 1 0 | 32-bit Interrupt Gate   |
    // | 15       1  1 1 1 | 32-bit Trap Gate        |
    // +-------------------+-------------------------+
    switch (d.h_dw.type) {
      case 0: case 8:  case 10: case 13:    HandleReserved(d); break;
      case 1: case 3:  case 9:  case 11:    HandleTSS(d);      break;
      case 2:                               HandleLDT(d);      break;
      case 4: case 12: /* call      gate */ HandleGate(d);     break;
      case 5:          /* task      gate */ HandleGate(d);     break;
      case 6: case 14: /* interrupt gate */ HandleGate(d);     break;
      case 7: case 15: /* trap      gate */ HandleGate(d);     break;
      default: printf("Invalid type: %#x\n", d.h_dw.type);     break;
    }
  } else {
    // Table 3-1. Code- and Data-Segment Types
    // (from Intel® 64 and IA-32 Arcitectures Software Developer's Manual 3A)
    //
    // +-------------------+------------+------------------------------------+
    // |    Type Field     | Descriptor |          Description               |
    // | Decimal 11 10 9 8 |    Type    |                                    |
    // +-------------------+------------+------------------------------------+
    // |             E W A |            |                                    |
    // | 0        0  0 0 0 |    Data    |              read-only             |
    // | 1        0  0 0 1 |    Data    |              read-only,   accessed |
    // | 2        0  0 1 0 |    Data    |              read/write            |
    // | 3        0  0 1 1 |    Data    |              read/write,  accessed |
    // | 4        0  1 0 0 |    Data    | expand-down  read-only,            |
    // | 5        0  1 0 1 |    Data    | expand-down, read-only,   accessed |
    // | 6        0  1 1 0 |    Data    | expand-down  read/write,           |
    // | 7        0  1 1 1 |    Data    | expand-down, read/write,  accessed |
    // |             C R A |            |                                    |
    // | 8        1  0 0 0 |    Code    |             execute-only           |
    // | 9        1  0 0 1 |    Code    |             execute-only, accessed |
    // | 10       1  0 1 0 |    Code    |             execute/read           |
    // | 11       1  0 1 1 |    Code    |             execute/read, accessed |
    // | 12       1  1 0 0 |    Code    | conforming, execute-only           |
    // | 13       1  1 0 1 |    Code    | conforming, execute-only, accessed |
    // | 14       1  1 1 0 |    Code    | conforming, execute/read           |
    // | 15       1  1 1 1 |    Code    | conforming, execute/read, accessed |
    // +-------------------+------------+------------------------------------+
    HandleCodeOrDataSegment(d);
  }
}

int main(void) {
  printf("Enter the segment descriptor in 4 words. "
         "Format: <low_word>, <low_mid_word>, <mid_high_word>, <high_word>\n");
  printf("Example:\n");
  printf("- 03ff, 0000, fa00, 00c0\n");
  printf("- 07ff, 0000, 9200, 00c0\n");
  printf("- 07ff, 0000, 9600, 00c0\n");
  printf("- 07ff, 0000, 9600, 0080\n");

  Descriptor desc;
  size_t l_dw_size = sizeof(desc.l_dw);
  size_t h_dw_size = sizeof(desc.h_dw);
  size_t desc_size = sizeof(desc);
  if (l_dw_size != 4 || h_dw_size != 4 || desc_size != 8) {
    printf("Size error: l_dw_size:%lu, h_dw_size:%lu, desc_size:%lu\n",
           l_dw_size, h_dw_size, desc_size);
  }

  unsigned int a, b, c, d;
  printf("> ");
  while (scanf("%x, %x, %x, %x", &a, &b, &c, &d) == 4) {
    unsigned int l_dw = ((b << 16) | a);
    unsigned int h_dw = ((d << 16) | c);
    desc.l_dw = *(DescriptorLowDWord*)&l_dw;
    desc.h_dw = *(DescriptorHighDWord*)&h_dw;
    Parse(desc);
    printf("> ");
  }
  return 0;
}
