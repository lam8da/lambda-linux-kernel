#!/bin/bash
set -x

install_tools() {
  brew install bochs
  brew install nasm
}
build_img() {
 # Copy the bin file to img file
 dd if=boot.bin of=boot.img bs=512 count=1 conv=notrunc
}
run() {
  bochs -q -f bochsrc.txt
}

run
