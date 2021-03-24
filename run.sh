set -x

# Note: in macos to use gcc we only need to install
# Command_Line_Tools_for_Xcode_xx.x.x.dmg, not xcode itself.

# Used in bochsrc.txt
IMG_FILE=bin/boot.img

install_tools() {
  # sudo chown -R $(whoami) /usr/local/bin /usr/local/etc /usr/local/sbin /usr/local/share /usr/local/share/doc
  sudo chown -R "$USER":admin /usr/local/share /usr/local/bin
  brew install bochs
  brew install nasm
}
diff_bin() {
  if [[ "$#" -ne 2 ]]; then
    >&2 echo -e "\e[93m Usage: diff_bin <file1> <file2> \e[0m"
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
    >&2 echo -e "\e[93m Usage: build_img <src> [<dd args>...] \e[0m"
    return
  fi
  local src="$1"
  shift
  local bin=${src//.asm/.bin}
  bin=${bin//src\//bin\/}
  nasm "$src" -f bin -o "$bin"

  # Copy the bin file to img file
  #
  # - bs=n: Set both input and output block size to n bytes, superseding the ibs
  #   and obs operands
  # - conv=notrunc: Do not truncate the output file. This will preserve any
  #   blocks in the output file not explicitly written by dd
  # - count=n: Copy only n input blocks.
  # - oseek=n: Seek on the output file n blocks.
  dd if="$bin" of="$IMG_FILE" bs=512 conv=notrunc "$@"
}
build_hello_world() {
  build_img experiment/hello_world_boot.asm count=1
}
build_two_process() {
  build_img experiment/two_process_boot.asm count=1
  build_img experiment/two_process_head.asm oseek=1
}
run() {
  local program=${program:-two_process}
  if [[ "$program" == 'hello_world' ]]; then
    build_hello_world
  elif [[ "$program" == 'two_process' ]]; then
    build_two_process
  fi
  unset_x
  >&2 echo -e "\e[93m ===> Type 'c' to start the virtual machine. \e[0m"
  >&2 echo -e "\e[93m ===> Note we can use the debugger to debug, try: \e[0m"
  >&2 echo -e "\e[93m      > b 0x7c00 \e[0m"
  >&2 echo -e "\e[93m      > u/10 \e[0m"
  >&2 echo -e "\e[93m ===> We can also use ndisasm command to disassemble the .bin/.img file. \e[0m"
  reset_x
  bochs -q -f bochsrc.txt
}
parse() {
  local name=segment_descriptor_parser
  gcc -o bin/$name.out experiment/$name.cc && ./bin/$name.out
}

if [[ "$#" -eq 0 ]]; then
  set run
fi
"$@"
