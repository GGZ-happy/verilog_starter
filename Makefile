###########################
# -- Table of Contents -- #
###########################
# Reference table of all make targets.

# ---- Compilation ---- #
# make synth/cpu.vg		<- synthesizes the CPU module from SOURCES to use in syn.simv
# make synth/*_stage.vg	<- synthesizes a stage of the CPU
# make simv				<- compiles simv from the TESTBENCH, HEADERS, and SOURCES
# make hsyn.simv		<- compiles hsyn.simv from TESTBENCH, HEADERS, verilog/cpu.sv, and SYNTH_STAGES
# make syn.simv			<- compiles syn.simv from TESTBENCH, HEADERS, and synth/cpu.vg
# make assemble_all		<- compiles/assembles all test programs

# ---- Program Execution ---- #
# these are your main commands for running programs and generating output
# make <program>.out		<- run a program on simv and output .out, .fmem, .cpi, and .wb files. Compare with correct out.
# make <program>.hsyn.out	<- run a program on hsyn.simv and do the same
# make <program>.syn.out	<- run a program on syn.simv and do the same
# make simulate_all			<- run make <program>.out for all programs.
# make simulate_all.hsyn	<- run make <program>.hsyn.out for all programs.
# make simulate_all.syn		<- run make <program>.syn.out for all programs.

# ---- Full Flow ---- #
# make full_flow_<STEPS>
#
#   <STEPS> is a combination of digits controlling which phases to run.
#
#     0   -- skip all phases, just (re-)generate report from existing data
#     1   -- run pre-synthesis simulation only
#     2   -- run synthesis only
#     3   -- run post-synthesis simulation only  (errors if synth/cpu.vg is missing)
#     12  -- pre-synthesis simulation + synthesis
#     13  -- pre-synthesis simulation + post-synthesis simulation
#     23  -- synthesis + post-synthesis simulation
#     123 -- full pipeline
#
#   Report is always generated at the end as full_report.txt.
#   "make full_flow" alone defaults to full_flow_123 (all three phases).
#
# make full_flow_fast_<STEPS>
#   Same as full_flow_<STEPS> but synthesis uses compile_ultra (slower, better optimization).
#   "make full_flow_fast" alone defaults to full_flow_fast_123.
#
# Examples:
#   make full_flow            <- run all three phases (default)
#   make full_flow_0          <- report only, no phases run
#   make full_flow_1          <- pre-syn simulation + report
#   make full_flow_2          <- synthesis + report
#   make full_flow_3          <- post-syn simulation + report
#   make full_flow_12         <- pre-syn + synthesis + report
#   make full_flow_23         <- synthesis + post-syn + report
#   make full_flow_123        <- same as make full_flow
#   make full_flow_fast_2     <- synthesis with compile_ultra + report
#   make full_flow_fast       <- full pipeline with compile_ultra

# ---- Submission ---- #
# ./submit proj

# make						<- runs the default target, set explicitly below as 'make walkthrough.out'
.DEFAULT_GOAL = walkthrough.out
# ^ this overrides using the first listed target as the default

# ---- Verdi ---- #
# make <my_program>.verdi		<- run a program in verdi via simv
# make <my_program>.hsyn.verdi	<- run a program in verdi via hsyn.simv
# make <my_program>.syn.verdi	<- run a program in verdi via syn.simv

# ---- Cleanup ---- #
# make clean		<- remove per-run output files
# make burn			<- remove compiled executable files
# make nuke			<- remove all files created from make rules including synthesized modules

######################################################
# ---- Compilation Commands and Other Variables ---- #
######################################################

# these are various build flags for different parts of the makefile, VCS and LIB should be
# familiar, but there are new variables for supporting the compilation of HSQ source programs 
# into machine code files to be loaded into the processor's memory

# don't be afraid to change these, but be diligent about testing changes and using git commits
# there should be no need to change anything for these labs

# remove certain warnings that generate MB of text but can be safely ignored
VCS_BAD_WARNINGS = +warn=noDEBUG_DEP +warn=noLCA_FEATURES_ENABLED
VCS_SYN_BAD_WARN = +warn=noTFIPC +warn=noENUMASSIGN

# the Verilog Compiler command and arguments
VCS = vcs -sverilog -xprop=tmerge +vc -Mupdate -line -full64 -kdb -lca -nc \
      -debug_access+all+reverse $(VCS_BAD_WARNINGS) +incdir+verilog/ +incdir+test/
# a SYNTH define is added when compiling for synthesis that can be used in testbenches

# Set the shell's pipefail option: causes return values through pipes to match the last non-zero value
# (useful for, i.e. piping to `tee`)
SHELL := $(SHELL) -o pipefail

# a reference library of standard structural cells that we link against when synthesizing
LIB = /usr/caen/misc/class/eecs470/lib/verilog/lec25dscc25.v

####################################
# ---- Executable Compilation ---- #
####################################

# NOTE: the executables are not the only things you need to compile
# you must also create a build/*.mem file for each program you run
# which will be loaded into test/mem.sv by the testbench on startup
# To run a program on simv or syn.simv, see the program execution section
# This is done automatically with 'make <my_program>.out'

HEADERS = $(wildcard verilog/*.svh) $(wildcard test/*.svh)

TESTBENCH = test/cpu_test.sv test/pipeline_print.c test/mem.sv

CPU = verilog/cpu.sv
CPU_SYN = synth/cpu.vg

# Using the wildcard in case you want to add your own sv files.
SOURCES = $(wildcard verilog/*.sv)
STAGES = $(wildcard verilog/stage_*.sv)
COMMON = $(filter-out verilog/cpu.sv $(STAGES), $(SOURCES))
SYNTH_FILES = $(CPU_SYN)
SYNTH_STAGES = $(STAGES:verilog/%.sv=synth/%.vg)

test:
	echo $(STAGES:verilog/%.sv=synth/%.vg)

.PHONY: test

$(CPU_SYN): $(SOURCES) $(HEADERS) 470synth.tcl cpu.clock | synth
	@$(call PRINT_COLOR, 3, synthesizing the cpu module. This might take a while...)
	export CLOCK_PERIOD="$(file < cpu.clock)" && \
	cd synth && \
	MODULE=cpu SOURCES="$(SOURCES)" \
	dc_shell-t -f ../470synth.tcl | tee cpu-synth.out
	@$(call PRINT_COLOR, 2, finished synthesizing $@ at $(file < cpu.clock)ns. Slack results below:)
	@grep "slack" synth/cpu.rep

# a make pattern rule to generate the .vg synthesis files
# pattern rules use the % as a wildcard to match multiple possible targets
synth/%.vg: verilog/%.sv $(COMMON) $(HEADERS) 470synth.tcl cpu.clock | synth
	@$(call PRINT_COLOR, 3, synthesizing the $* module. This might take a while...)
	export CLOCK_PERIOD="$(file < cpu.clock)" && \
	cd synth && \
	MODULE=$* SOURCES="$< $(COMMON)" \
	dc_shell-t -f ../470synth.tcl | tee $*-synth.out
	@$(call PRINT_COLOR, 2, finished synthesizing $@)

.SECONDARY:

# the normal simulation executable will run your testbench on the original modules
build/simv: cpu.clock $(TESTBENCH) $(SOURCES) $(HEADERS) | build
	@$(call PRINT_COLOR, 3, compiling the simulation executable $@)
	$(VCS) +lint=TFIPC-L $(filter-out $< $(HEADERS), $^) +define+CLOCK_PERIOD="$(file < $<)" -o $@
	-rm -r csrc vc_hdrs.h
	@$(call PRINT_COLOR, 2, finished compiling $@)

# the half synthesis executable runs your testbench on the original cpu with synthesized stage modules
build/hsyn.simv: cpu.clock $(TESTBENCH) $(CPU) $(SYNTH_STAGES) $(HEADERS) | build
	@$(call PRINT_COLOR, 3, compiling the half synthesis executable $@)
	$(VCS) $(VCS_SYN_BAD_WARN) $(filter-out $< $(HEADERS), $^) $(LIB) +define+CLOCK_PERIOD="$(file < $<)" -o $@
	-rm -r csrc vc_hdrs.h
	@$(call PRINT_COLOR, 2, finished compiling $@)

# the synthesis executable runs your testbench on the synthesized versions of your cpu module
build/syn.simv: cpu.clock $(TESTBENCH) $(SYNTH_FILES) $(HEADERS) | build
	@$(call PRINT_COLOR, 3, compiling the synthesis executable $@)
	$(VCS) $(VCS_SYN_BAD_WARN) $(filter-out $< $(HEADERS), $^) $(LIB) +define+CLOCK_PERIOD="$(file < $<)" -o $@
	-rm -r csrc vc_hdrs.h
	@$(call PRINT_COLOR, 2, finished compiling $@)

%.vg:	synth/%.vg ;
simv:	build/simv ;
%.simv: build/%.simv ;
.PHONY: %.vg simv %.simv

########################################
# ---- Program Memory Compilation ---- #
########################################

# this section will compile programs into .mem files to be loaded into memory
# you start with either an LC2K assembly program in the programs/ directory
# then that file is assembled to a .mem hex file

ASSEMBLY = $(wildcard programs/*.lc2k)

# concatenate ASSEMBLY and C_CODE to list every program
PROGRAMS = $(ASSEMBLY:%.lc2k=%)

# NOTE: this is Make's pattern substitution syntax
# see: https://www.gnu.org/software/make/manual/html_node/Text-Functions.html#Text-Functions
# this reads as: $(var:pattern=replacement)
# a percent sign '%' in pattern is as a wildcard, and can be reused in the replacement
# if you don't include the percent it automatically attempts to replace just the suffix of the input

# make elf files from assembly code
programs/build/%.mem: programs/%.lc2k | programs/build
	@$(call PRINT_COLOR, 5, assembling assembly file $<)
	programs/assembler-lc2k.exe $< $@

# compile all programs in one command (use 'make -j' to run multithreaded)
assemble_all: $(PROGRAMS:programs/%=programs/build/%.mem)
.PHONY: assemble_all

###############################
# ---- Program Execution ---- #
###############################

# run one of the executables (simv) using the chosen program
# e.g. 'make sampler.out' frorm a clean directory does the following:
#   1. compiles simv
#   2. compiles programs/sampler.s into its .elf and then .mem files (in programs/)
#   3. runs cd build && ./simv +MEMORY=../programs/sampler.mem +OUTPUT=../output/sampler > ../output/sampler.out
#   4. which creates the sampler.out, sampler.cpi, sampler.wb, and sampler.ppln files in output/
# the same can be done for synthesis by doing 'make sampler.syn.out'
# which will also create .syn.cpi, .syn.wb, and .syn.ppln files in output/

# run a program and produce output files
# run a program and produce output files
output/%.out: programs/build/%.mem build/simv | output
	cd build && ./simv -suppress=ASLR_DETECTED_INFO +MEMORY=../$< +OUTPUT=../output/$*
	@echo "checking output/$*.fmem against correct/syn/$*.fmem"
	@if [ ! -f correct/syn/$*.fmem ]; then \
		echo "WARNING: correct/syn/$*.fmem not found"; \
	elif [ ! -f output/$*.fmem ]; then \
		echo "ERROR: output/$*.fmem not found"; \
		exit 1; \
	elif cmp -s output/$*.fmem correct/syn/$*.fmem; then \
		echo "fmem check PASSED for $*"; \
	else \
		echo "fmem check FAILED for $*"; \
		diff -u correct/syn/$*.fmem output/$*.fmem > output/$*.fmem.diff || true; \
		echo "See output/$*.fmem.diff"; \
		exit 1; \
	fi
	@echo "finished running simv on $<"

# run half synthesis with: 'make <my_program>.hsyn'
# this does the same as simv, but adds .hsyn to the output files and compiles hsyn.simv instead
output_hsyn/%.out: programs/build/%.mem build/hsyn.simv | output_hsyn
	cd build && ./hsyn.simv -suppress=ASLR_DETECTED_INFO +MEMORY=../$< +OUTPUT=../output_hsyn/$*
	@echo "checking output_hsyn/$*.fmem against correct/syn/$*.fmem"
	@if [ ! -f correct/syn/$*.fmem ]; then \
		echo "WARNING: correct/syn/$*.fmem not found"; \
	elif [ ! -f output_hsyn/$*.fmem ]; then \
		echo "ERROR: output_hsyn/$*.fmem not found"; \
		exit 1; \
	elif cmp -s output_hsyn/$*.fmem correct/syn/$*.fmem; then \
		echo "fmem check PASSED for $*"; \
	else \
		echo "fmem check FAILED for $*"; \
		diff -u correct/syn/$*.fmem output_hsyn/$*.fmem > output_hsyn/$*.fmem.diff || true; \
		echo "See output_hsyn/$*.fmem.diff"; \
		exit 1; \
	fi
	@echo "finished running hsyn.simv on $<"

# run synthesis with: 'make <my_program>.syn'
# this does the same as simv, but adds .syn to the output files and compiles syn.simv instead
output_syn/%.out: programs/build/%.mem build/syn.simv | output_syn
	cd build && ./syn.simv -suppress=ASLR_DETECTED_INFO +MEMORY=../$< +OUTPUT=../output_syn/$*
	@echo "checking output_syn/$*.fmem against correct/syn/$*.fmem"
	@if [ ! -f correct/syn/$*.fmem ]; then \
		echo "WARNING: correct/syn/$*.fmem not found"; \
	elif [ ! -f output_syn/$*.fmem ]; then \
		echo "ERROR: output_syn/$*.fmem not found"; \
		exit 1; \
	elif cmp -s output_syn/$*.fmem correct/syn/$*.fmem; then \
		echo "fmem check PASSED for $*"; \
	else \
		echo "fmem check FAILED for $*"; \
		diff -u correct/syn/$*.fmem output_syn/$*.fmem > output_syn/$*.fmem.diff || true; \
		echo "See output_syn/$*.fmem.diff"; \
		exit 1; \
	fi
	@echo "finished running syn.simv on $<"

# Allow us to type 'make <my_program>.out' instead of 'make output/<my_program>.out'
./%.out: output/%.out ;

# Allow us to type 'make <my_program>.hsyn' instead of 'make output_hsyn/<my_program>.out'
./%.hsyn: output_hsyn/%.out ;
./%.syn: output_syn/%.out ;

.PHONY: ./%.out ./%.hsyn ./%.syn

.PRECIOUS: programs/build/%.asq programs/build/%.sq programs/build/%.mem output/%.out output_hsyn/%.out output_syn/%.out

# Declare that creating a %.out file also creates both %.cpi, %.wb, and %.ppln files
%.cpi %.wb %.fmem %.ppln: %.out ;

# run all programs in one command (use 'make -j' to run multithreaded)
simulate_all: build/simv assemble_all $(PROGRAMS:programs/%=output/%.out)
	@$(call PRINT_COLOR, 5, extracting CPI summary from output/)
	./extract_cpi.sh ./output cpi_summary
	@$(call PRINT_COLOR, 2, CPI summary generated)

simulate_all.hsyn: build/hsyn.simv assemble_all $(PROGRAMS:programs/%=output_hsyn/%.out)
	@$(call PRINT_COLOR, 5, extracting CPI summary from output_hsyn/)
	./extract_cpi.sh ./output_hsyn cpi_summary_hsyn
	@$(call PRINT_COLOR, 2, CPI hsyn summary generated)

simulate_all.syn: build/syn.simv assemble_all $(PROGRAMS:programs/%=output_syn/%.out)
	@$(call PRINT_COLOR, 5, extracting CPI summary from output_syn/)
	./extract_cpi.sh ./output_syn cpi_summary_syn
	@$(call PRINT_COLOR, 2, CPI syn summary generated)

.PHONY: simulate_all simulate_all.hsyn simulate_all.syn

#########################################
# ----        Full Flow            ---- #
#########################################
#
# Use make full_flow_<STEPS> where <STEPS> is a combination of:
#   1 = pre-synthesis simulation  (simulate_all     -> output/)
#   2 = synthesis                 (synth/cpu.vg     -> synth/)
#   3 = post-synthesis simulation (simulate_all.syn -> output_syn/)
#       NOTE: step 3 requires synth/cpu.vg to exist; it will error if missing.
#
# "make full_flow" alone is equivalent to "make full_flow_123".
# "make full_flow_fast" alone is equivalent to "make full_flow_fast_123".
#
# Examples:
#   make full_flow        <- full pipeline (all 3 phases)
#   make full_flow_0      <- report only from existing data
#   make full_flow_1      <- pre-syn simulation + report
#   make full_flow_2      <- synthesis + report
#   make full_flow_3      <- post-syn simulation + report
#   make full_flow_12     <- pre-syn + synthesis + report
#   make full_flow_23     <- synthesis + post-syn + report
#   make full_flow_123    <- same as make full_flow
#   make full_flow_fast   <- full pipeline with compile_ultra
#   make full_flow_fast_2 <- synthesis with compile_ultra + report

full_flow_%:
	@if echo "$*" | grep -q "1"; then \
		echo ""; \
		$(call PRINT_COLOR, 4, === Phase 1: pre-synthesis simulation ===); \
		$(MAKE) simulate_all || exit 1; \
	fi
	@if echo "$*" | grep -q "2"; then \
		echo ""; \
		$(call PRINT_COLOR, 4, === Phase 2: synthesis ===); \
		$(MAKE) synth/cpu.vg || exit 1; \
	fi
	@if echo "$*" | grep -q "3"; then \
		echo ""; \
		if [ ! -f synth/cpu.vg ]; then \
			$(call PRINT_COLOR, 1, ERROR: synth/cpu.vg not found.); \
			echo "Run synthesis first (e.g. make full_flow_23)."; \
			exit 1; \
		fi; \
		$(call PRINT_COLOR, 4, === Phase 3: post-synthesis simulation ===); \
		$(MAKE) simulate_all.syn || exit 1; \
	fi
	@echo ""
	@$(call PRINT_COLOR, 5, === Generating combined report ===)
	@mkdir -p ./output ./output_syn synth
	@./full_report.sh ./output ./output_syn synth/cpu.rep full_report
	@$(call PRINT_COLOR, 2, full_flow_$* complete - see full_report.txt)

full_flow_fast_%:
	@if echo "$*" | grep -q "1"; then \
		echo ""; \
		$(call PRINT_COLOR, 4, === Phase 1: pre-synthesis simulation ===); \
		$(MAKE) simulate_all || exit 1; \
	fi
	@if echo "$*" | grep -q "2"; then \
		echo ""; \
		$(call PRINT_COLOR, 4, === Phase 2: synthesis with compile_ultra ===); \
		rm -f synth/cpu.vg; \
		export CLOCK_PERIOD="$(file < cpu.clock)" && \
		cd synth && \
		MODULE=cpu SOURCES="$(SOURCES)" COMPILE_ULTRA=1 \
		dc_shell-t -f ../470synth.tcl | tee cpu-synth.out || exit 1; \
		$(call PRINT_COLOR, 2, finished synthesizing with compile_ultra. Slack results below:); \
		grep "slack" synth/cpu.rep; \
	fi
	@if echo "$*" | grep -q "3"; then \
		echo ""; \
		if [ ! -f synth/cpu.vg ]; then \
			$(call PRINT_COLOR, 1, ERROR: synth/cpu.vg not found.); \
			echo "Run synthesis first (e.g. make full_flow_fast_23)."; \
			exit 1; \
		fi; \
		$(call PRINT_COLOR, 4, === Phase 3: post-synthesis simulation ===); \
		$(MAKE) simulate_all.syn || exit 1; \
	fi
	@echo ""
	@$(call PRINT_COLOR, 5, === Generating combined report ===)
	@mkdir -p ./output ./output_syn synth
	@./full_report.sh ./output ./output_syn synth/cpu.rep full_report_fast
	@$(call PRINT_COLOR, 2, full_flow_fast_$* complete - see full_report_fast.txt)

# Default aliases: no suffix = run all three phases
full_flow: full_flow_123 ;
full_flow_fast: full_flow_fast_123 ;

.PHONY: full_flow full_flow_fast

###################
# ---- Verdi ---- #
###################

# Options to launch Verdi when running the executable
RUN_VERDI_OPTS = -gui=verdi -verdi_opts "-ultra" -no_save
# Not sure why no_save is needed right now. Otherwise prints an error
VERDI_DIR = /tmp/$(USER)470
VERDI_TEMPLATE = /usr/caen/misc/class/eecs470/verdi-config/initialnovas.rc

# verdi hates us: we must use the /tmp folder for all verdi files or it will crash
# this adds much unecessary complexity in the makefile
# A directory for verdi, specified in the build/novas.rc file.
$(VERDI_DIR) $(VERDI_DIR)/verdiLog:
	mkdir -p $@
# Symbolic link from the build folder to VERDI_DIR in /tmp
build/verdiLog: $(VERDI_DIR) build
	ln --force -s $(VERDI_DIR)/verdiLog build
# make a custom novas.rc for your username matching VERDI_DIR
build/novas.rc: $(VERDI_TEMPLATE) | build
	sed s/UNIQNAME/$${USER}/ $< > $@

# now the actual targets to launch verdi
%.verdi: programs/build/%.mem build/simv build/novas.rc build/verdiLog $(VERDI_DIR) | output
	cd build && ./simv $(RUN_VERDI_OPTS) +MEMORY=../$< +OUTPUT=../output/verdi_output

%.hsyn.verdi: programs/build/%.mem build/hsyn.simv build/novas.rc build/verdiLog $(VERDI_DIR) | output_hsyn
	cd build && ./hsyn.simv $(RUN_VERDI_OPTS) +MEMORY=../$< +OUTPUT=../output_hsyn/verdi_output

%.syn.verdi: programs/build/%.mem build/syn.simv build/novas.rc build/verdiLog $(VERDI_DIR) | output_syn
	cd build && ./syn.simv $(RUN_VERDI_OPTS) +MEMORY=../$< +OUTPUT=../output_syn/verdi_output

.PHONY: %.verdi %.hsyn.verdi %.syn.verdi

###############################
# ---- Build Directories ---- #
###############################

# Directories for holding build files or run outputs
# Targets that need these directories should add them after a pipe.
# ex: "target: dep1 dep2 ... | build"
build synth output output_hsyn output_syn programs/build:
	mkdir -p $@
# Don't leave any files in these, they will be deleted by clean commands

#####################
# ---- Cleanup ---- #
#####################

clean:
	@$(call PRINT_COLOR, 2, removing per-run output files)
	-rm -rf output* *.vcd

burn: clean
	@$(call PRINT_COLOR, 6, note: you can call \"make $^\" to not remove compiled executables)
	@$(call PRINT_COLOR, 3, removing compiled executable files)
	-rm -rf build *simv *.daidir csrc *.key vcdplus.vpd vc_hdrs.h unifiedInference.log xprop.log
	-rm -rf verdi* novas* *fsdb* dve* inter.vpd DVEfiles

# removes all extra synthesis files and the compiled test programs
# use cautiously: this can cause hours of recompiling in the final project
nuke: burn
	@$(call PRINT_COLOR, 6, note: you can call \"make $^\" to not remove synthesis files)
	@$(call PRINT_COLOR, 1, removing synthesis files)
	-rm -rf programs/build *.mem
	rm -rf synth *.vg *_svsim.sv *.res *.rep *.ddc *.chk *.syn *-synth.out *.db *.svf *.mr *.pvl command.log cksum_dir

.PHONY: clean burn nuke

######################
# ---- Printing ---- #
######################

PRINT_COLOR = if [ -t 0 ]; then tput setaf $(1) ; fi; echo $(2); if [ -t 0 ]; then tput sgr0; fi
# colors: 0:black, 1:red, 2:green, 3:yellow, 4:blue, 5:magenta, 6:cyan, 7:white
