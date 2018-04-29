#include <stdio.h>
#include <string.h>

// 定义描述符中的低32位
struct DescriptorLowDWord {
  unsigned int limit_0_15 : 16;  // 段限长0-15位
  unsigned int base_0_15 : 16;   // 基地址0-15位
};

// 定义描述符中的高32位(通用格式)
struct DescriptorHighDWord {
  unsigned int base_16_23 : 8;   // 基地址16-23位
  unsigned int type : 4;         // 段类型
  unsigned int s : 1;            // 描述符类型，0是系统描述符，1是代码或数据
  unsigned int dpl : 2;          // 特权级
  unsigned int p : 1;            // 段是否存在于内存中
  unsigned int limit_16_19 : 4;  // 段限长16-19位
  unsigned int avl : 1;          // 无预定义功能，可由操作系统任意使用
  unsigned int l : 1;            // 保留给64位处理器使用
  unsigned int d_b : 1;          // 1表示代码/数据/堆栈段运行于32位模式，0是16位
  unsigned int g : 1;            // 段限长的scaling factor，0/1表示以1/4KB位单位
  unsigned int base_24_31 : 8;   // 基地址24-32位
};

struct Descriptor {
  DescriptorLowDWord l_dw;
  DescriptorHighDWord h_dw;
};

/*
  int offset = (hig_dw & 0xFFFF0000) | (low_dw & 0x0000FFFF);
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
      printf("16位中断门，段选择子 = %#x，偏移 = %#x\n", pl->base_0_15, offset);
    } else if (type == 14) {
      printf("32位中断门，段选择子 = %#x，偏移 = %#x\n", pl->base_0_15, offset);
    } else if (type == 7) {
      printf("16位陷阱门，段选择子 = %#x，偏移 = %#x\n", pl->base_0_15, offset);
    } else if (type == 15) {
      printf("32位陷阱门，段选择子 = %#x，偏移 = %#x\n", pl->base_0_15, offset);
    } else if (type == 12) {
      printf("调用门，段选择子 = %#x，偏移 = %#x , 参数个数 = %d\n",
             pl->base_0_15,
             offset,
             hig_dw & 0x1F);
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
  printf("Reserved\n");
}

void HandleTSS(Descriptor d) {
  printf("Task-state segment (TSS) descriptor\n");
}

void HandleLDT(Descriptor d) {
  printf("Local descriptor-table (LDT) segment descriptor\n");
}

void HandleCallGate(Descriptor d) {
  printf("Call-gate descriptor\n");
}

void HandleTaskGate(Descriptor d) {
  printf("Task-gate descriptor\n");
}

void HandleInterruptGate(Descriptor d) {
  printf("Interrupt-gate descriptor\n");
}

void HandleTrapGate(Descriptor d) {
  printf("Trap-gate descriptor\n");
}

// Reference:
// - https://blog.csdn.net/longintchar/article/details/78881396
// - "Figure 5-1. Descriptor Fields Used for Protection" of 
//   Intel® 64 and IA-32 Arcitectures Software Developer's Manual 3A
const char *kSegmentFormat =
"\n"
" 31              24         19    16         11    8 7                0\n"
"+------------------+-+-+-+-+--------+-+---+-+-------+------------------+\n"
"|   Base Address   | | | |A|  Limit | |   | | TYPE  |   Base Address   |\n"
"|      31..24      |G|%s|L|V| 19..16 |P|DPL|S|-------|     23..16       |\n"
"|                  | | | |L|        | |   | |  %s|                  |\n"
"+------------------+-+-+-+-+--------+-+---+-+-------+------------------+ 4\n"
"        %02x          %d %d %d %d    %x     %d  %d  %d %d %d %d %d         %02x\n"
"+-----------------------------------+----------------------------------+\n"
"|           Base Address            |          Segment Limit           |\n"
"|               15..0               |              15..0               |\n"
"|                                   |                                  |\n"
"+-----------------------------------+----------------------------------+ 0\n"
"                %04x                               %04x\n";

void HandleCodeOrDataSegment(Descriptor d) {
  int is_code = ((d.h_dw.type & 8) >> 3);
  int type_0x4 = ((d.h_dw.type & 4) >> 2);
  int type_0x2 = ((d.h_dw.type & 2) >> 1);
  int type_0x1 = (d.h_dw.type & 1);
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
  printf("- segment base address: %#010x\n", SegmentBase(d));
  printf("- segment limit: %#010x", limit);
  if (g) printf("=%dK-1", (limit+1) >> 10);
  if (is_code || type_0x4 == 0) {
    // Expand up.
    printf(", range is [%#010x, %#010x] (expand-up)\n", 0, limit);
  } else {
    printf(", range is [%#010x, %#010x]",
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
    printf("- expand-down data segment only: upper bound of the segment is %s "
           "(B=%d)\n",
           (d_b ? "0xffffffff" : "0xffff"), d_b);
  }

  // P, DPL, S
  printf("- segment %s in memory (P=%d)\n",
         (p ? "presents" : "doesn't present"), p);
  printf("- descriptor privilege level (DPL, 0 is the most): %d\n", dpl);
  printf("- descriptor type: %s segment (S=%d)\n",
         s ? "system" : "code or data", s);

  // Type
  printf("- type %x: ", d.h_dw.type);
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
         d.h_dw.base_24_31, g, d_b, d.h_dw.l, d.h_dw.avl,
         d.h_dw.limit_16_19, p, dpl, s,
         is_code, type_0x4, type_0x2, type_0x1, d.h_dw.base_16_23,
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
      case 0: case 8:  case 10: case 13: HandleReserved(d);      break;
      case 1: case 3:  case 9:  case 11: HandleTSS(d);           break;
      case 2:                            HandleLDT(d);           break;
      case 4: case 12:                   HandleCallGate(d);      break;
      case 5:                            HandleTaskGate(d);      break;
      case 6: case 14:                   HandleInterruptGate(d); break;
      case 7: case 15:                   HandleTrapGate(d);      break;
      default: printf("Invalid type: %#x\n", d.h_dw.type);       break;
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
         "Format: <low_word> <low_mid_word> <mid_high_word> <high_word>\n");
  printf("Example:\n");
  printf("- 03ff 0000 fa00 00c0\n");
  printf("- 07ff 0000 9200 00c0\n");
  printf("- 07ff 0000 9600 00c0\n");
  printf("- 07ff 0000 9600 0080\n");

  Descriptor descriptor;
  unsigned int a, b, c, d;
  printf("> ");
  while (scanf("%x %x %x %x", &a, &b, &c, &d) == 4) {
    unsigned int l_dw = ((b << 16) | a);
    unsigned int h_dw = ((d << 16) | c);
    descriptor.l_dw = *(DescriptorLowDWord*)&l_dw;
    descriptor.h_dw = *(DescriptorHighDWord*)&h_dw;
    Parse(descriptor);
    printf("> ");
  }
  return 0;
}
