#!/bin/bash
# build.sh
#
# Assembles and links the maze game.
# Usage: ./build.sh
#
# Requires: nasm, ld (binutils) -- both standard on WSL2 Ubuntu.
# Install with: sudo apt install nasm binutils

set -e

echo "Assembling..."
for f in *.asm; do
    nasm -f elf64 -g -F dwarf "$f" -o "${f%.asm}.o"
done

echo "Linking..."
ld -o Maze_game *.o

echo "Build complete: ./Maze_game"
echo "Run it with: ./Maze_game"
