#!/bin/bash
set -x

bin=/tmp/segment_descriptor_parser
output=/tmp/segment_descriptor_parser_output-$RANDOM

gcc -o $bin segment-descriptor-parser.cc

$bin > $output <<EOF
03ff, 0000, fa00, 00c0
07ff, 0000, 9200, 00c0
07ff, 0000, 9600, 00c0
07ff, 0000, 9600, 0080
0x07FF, 0x0000, 0x9A00, 0x00C0
0x07FF, 0x0000, 0x9200, 0x00C0
0x0002, 0x8000, 0x920B, 0x00C0
EOF

diff $output segment_descriptor_parser.testdata
