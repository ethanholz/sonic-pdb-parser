# Sonic PDB Parser
A WIP sonic-speed PDB parser written in Zig. This project contains 2 binaries and a shared library/module for use with other Zig projects. 

## Usage
`main -r <runs> -f <file> -o <output>`
- `-r` -> specifies the number of times to run test, if r = 1, this will print the parsed file
- `-f` -> specifies the file you want to parse
- `-o` -> specifies the CSV you want to output to 
- `--json` -> if r = 1, print the output as JSON
