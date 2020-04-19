#!/bin/bash
set -x

IMG_FILE=bin/boot.img

install_tools() {
  # sudo chown -R $(whoami) /usr/local/bin /usr/local/etc /usr/local/sbin /usr/local/share /usr/local/share/doc
  sudo chown -R "$USER":admin /usr/local/share /usr/local/bin
  brew install bochs
  brew install nasm
}
diff_bin() {
  if [[ "$#" -ne 2 ]]; then
    echo 'Usage: diff_bin <file1> <file2>'
    return
  fi
  local o1=/tmp/hexdump-"$1"
  local o2=/tmp/hexdump-"$2"
  xxd "$1" > "$o1"
  xxd "$2" > "$o2"
  diff "$o1" "$o2"
}
build_img() {
  if [[ "$#" -lt 1 ]]; then
    echo 'Usage: build_img <src> [<dd args>...]'
    return
  fi
  local src="$1"
  shift
  local bin=${src//.asm/.bin}
  bin=${bin//src\//bin\/}
  nasm "$src" -f bin -o "$bin"
  # Copy the bin file to img file
  dd if="$bin" of="$IMG_FILE" bs=512 conv=notrunc "$@"
}
build_hello_world() {
  build_img src/hello_world_boot.asm count=1
}
build_two_process() {
  build_img src/two_process_boot.asm count=1
  build_img src/two_process_head.asm oseek=1
}
run() {
  unset_x
  echo "===> Type 'c' to start the virtual machine."
  echo "===> Note we can use the debugger to debug, try:"
  echo "     > b 0x7c00"
  echo "     > u/10"
  echo "===> We can also use ndisasm command to disassemble the .bin/.img file."
  reset_x
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
