# Sonic PDB Parser
A WIP sonic-speed PDB parser written in Zig. This project contains two modules (sonic and sonic-fasta) for importing into other Zig projects. Furthermore, there are two binaries, one for parsing and benchmarking PDB parsing (`sonic-pdb-parser`) and another for converting PDB files to FASTA files (`pdb2fasta`).

## Usage - sonic-pdb-parser
`sonic-pdb-parser -r <runs> -f <file> -o <output>`
- `-r` -> specifies the number of times to run test, if r = 1, this will print the parsed file
- `-f` -> specifies the file you want to parse
- `-o` -> specifies the CSV you want to output to 
- `--json` -> if r = 1, print the output as JSON

## Usage - pdb2fasta
`pdb2fasta -f <file>.pdb -o <out>.fasta`
- `-f` -> specifies the file you want to convert
- `-o` -> specifies the output FASTA file

## Goals 
- [ ] Be able to completely parse the wwPDB 3.3 spec
- [ ] Provide WASM and/or C bindings
- [ ] Integrate FASTA conversion (BETA)

### References 
[pdb2fasta](https://github.com/kad-ecoli/pdb2fasta)
