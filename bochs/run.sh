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
  local bin=${asm//.asm/.bin}
  nasm "$asm" -f bin -o "$bin"
  # Copy the bin file to img file
  dd if="$bin" of="$IMG_FILE" bs=512 count=1 conv=notrunc
}
run() {
  build_img "$1"
  bochs -q -f bochsrc.txt
}

# Type 'continue' or 'c' to start the virtual machine.
run hello-world-boot.asm
