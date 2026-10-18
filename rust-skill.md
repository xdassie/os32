#NB NB For CORE DIRECTIVES for Rust development:
1. Avoid using shell commands to edit files. Edit the files directly.
2. DO NOT EVER use the sed command to edit files. NEVER
3. DO NOT EVER edit ANY file without asking the USER first
4. proceed autonomously. run ./agentmenu.sh in the current direcctory to test the program and do not attempt to change 
the current directory nor run any other commands when testing the program. DO NOT EDIT agentmenu.sh
5. _NEVER_ include prototype code or fallback code in the main code base. e.g. NEVER this: simplifed...use XYZ for  proper...
6. english is too much typing. use a concise shorthand  a bit like assembly language for interacting with the user. e..Concept: Map file paths to R0-R.. registers:
+-------+----------------+--------------------------------+------------------+
| OPCODE| PHASE          | DESCRIPTION                    | SYNTAX EXAMPLE   |
+-------+----------------+--------------------------------+------------------+
| LD    | LOAD           | Load file into Register        | LD R0 ./src.py   |
| PR    | PRINT          | Output Register content        | PR R0            |
| CMP   | COMPARE        | Compare two files              | CMP R1 R2        |
| APP   | APPEND         | Add lines to file              | APP R0 5 "text"  |
| DEL   | DELETE         | Remove lines from file         | DEL R0 3         |
| RPL   | REPLACE        | Replace lines in file          | RPL R0 1 "text"  |
| RDR   | READ/RUN       | Execute shell command          | RDR "ls -la"     |
| GTP   | GREP           | Search text in file            | GTP R0 "error"   |
| CRT   | CREATE         | Create new file path           | CRT R3 ./new.txt |
| DPT   | DEPLOY         | Simulate deployment step       | DPT R0 prod      |
| LOG   | LOG            | Record action to log           | LOG R9 "done"    |
| CHK   | CHECK          | Validate state/exit code (see rule #4)       | CHK R0           |
| JMP   | JUMP           | Skip/Loop logic (meta)         | JMP L1           |
| LBL   | LABEL          | Define label for jump          | LBL L1           |
| SKLR  | META  | Re-read this file (DO NOT USE A CACHED COPY)              | SKLR             |
| MOD  | CREATE         | Add a new module               | MOD <location> <purpose>|
| LODW | LOAD           | Load multiple registers from a wildcard | LODW <wildcard> |
| REG  | PRINT          | Print values in all registers     | REG             |
| PTC  | PATCH   | Edit a specific file only with the changes required according to the current context  | PTC r3    |
| PLN  | PLAN          | Plan the given goal     | PLN <goal>             |
+-------+----------------+--------------------------------+------------------+
7. When generating a plan, use the mnemonic format defined in (6) in this file to express the plan as far as possible (you are permitted to propose changes to the mnemonics but not change them without the user's consent)
8. Never run cargo clean. If you suspect some kind of symbol or object file conflict, stop and alert the user.

