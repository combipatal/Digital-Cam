@echo off

start iverilog -o %1.vvp %1.v
start vvp %1.vvp
start gtkwave %1.vcd

GOTO:EOF