#!/bin/bash
set -x

name=segment_descriptor_parser
bin=/tmp/${name}.out
output=/tmp/${name}_output-$RANDOM

gcc -o $bin ${name}.cc

# Order: code, data, interrupt, trap, call, task
$bin > $output <<EOF
03ff, 0000, fa00, 00c0
07ff, 0000, 9a00, 00c0

07ff, 0000, 9200, 00c0
07ff, 0000, 9600, 00c0
07ff, 0000, 9600, 0080
07ff, 0000, 9200, 00c0
0002, 8000, 920b, 00c0

0000, 0008, 8e00, 0000

0000, 0008, ef00, 0000
EOF

# 0x0068, 0x1111, 0xE900, 0x0000

diff ${name}.testdata $output
