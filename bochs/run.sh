#!/bin/bash
set -x

IMG_FILE=boot.img

install_tools() {
  sudo chown -R "$USER":admin /usr/local/share /usr/local/bin
  brew install bochs
  brew install nasm
}
diff_bin() {
  local o1=/tmp/hexdump-"$1"
  local o2=/tmp/hexdump-"$2"
  xxd "$1" > "$o1"
  xxd "$2" > "$o2"
  diff "$o1" "$o2"
}
build_img() {
  local asm=${1:-boot.asm}
	shift
  local bin=${asm//.asm/.bin}
  nasm "$asm" -f bin -o "$bin"
  # Copy the bin file to img file
  dd if="$bin" of="$IMG_FILE" bs=512 conv=notrunc "$@"
}
build_hello_world() {
  build_img hello_world_boot.asm count=1
}
build_two_process() {
  build_img two_process_boot.asm count=1
  build_img two_process_head.asm oseek=1
}
run() {
	reset_x_if_set
	echo "===> Type 'c' to start the virtual machine."
	echo "===> Note we can use the debugger to debug, try:"
	echo "     > b 0x7c00"
	echo "     > u/10"
	echo "===> We can also use ndisasm command to disassemble the .bin/.img file."
	set_x_if_set
  bochs -q -f bochsrc.txt
}
run_segment_descriptor_parser() {
	local name=segment_descriptor_parser
	gcc -o $name.out $name.cc && ./$name.out
}

# build_hello_world
build_two_process
run
# run_segment_descriptor_parser
