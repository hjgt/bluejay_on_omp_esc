# Current version
TAG			:= $(shell git describe --tags --abbrev=0)
VERSION		?= $(TAG)

# Target parameters
LAYOUTS		= A B C D E F G H I J K L M N O P Q R S T U V W Z \
			  OA
MCUS			= H
LAYOUTS_X		= A B C
MCUS_X		= X
DEADTIMES		= 0 5 10 15 20 25 30 40 50 70 90 120
PWM_FREQS		= 24 48 96

# Custom OMP ESC target. The FD6288 needs complementary HIN/LIN PWM, so the
# DEADTIME=0 targets used by some discrete-driver layouts are deliberately not
# generated for this board.
OMP_LAYOUTS		= X
OMP_MCUS		= H
OMP_DEADTIMES	= $(filter-out 0,$(DEADTIMES))

# Layout numbers encoded in the firmware tag. Keep these in sync with the
# layout enumerations in src/Bluejay.asm. Using make variables here avoids
# launching several shell processes for every generated target rule.
ESCNO_A := 1
ESCNO_B := 2
ESCNO_C := 3
ESCNO_D := 4
ESCNO_E := 5
ESCNO_F := 6
ESCNO_G := 7
ESCNO_H := 8
ESCNO_I := 9
ESCNO_J := 10
ESCNO_K := 11
ESCNO_L := 12
ESCNO_M := 13
ESCNO_N := 14
ESCNO_O := 15
ESCNO_P := 16
ESCNO_Q := 17
ESCNO_R := 18
ESCNO_S := 19
ESCNO_T := 20
ESCNO_U := 21
ESCNO_V := 22
ESCNO_W := 23
ESCNO_X := 24
ESCNO_Y := 25
ESCNO_Z := 26
ESCNO_OA := 27

# Example single target
LAYOUT		?= A
MCU			?= H
DEADTIME	?= 5
PWM			?= 24

# Directory configuration
OUTPUT_DIR	?= build
HEX_DIR		?= $(OUTPUT_DIR)/hex

# Path to the keil binaries
KEIL_PATH	?= ~/.wine/drive_c/Keil_v5/C51/BIN

# Assembler and linker binaries
AX51_BIN	= $(KEIL_PATH)/AX51.exe
LX51_BIN	= $(KEIL_PATH)/LX51.exe
OX51_BIN	= $(KEIL_PATH)/Ohx51.exe
AX51		= wine $(AX51_BIN)
LX51		= wine $(LX51_BIN)
OX51		= wine $(OX51_BIN)

# Set up flags
#AX51_FLAGS	= DEBUG NOMOD51
AX51_FLAGS	= NOMOD51 REGISTERBANK(0,1,2) NOLIST NOSYMBOLS
LX51_FLAGS	=

# Source files
ASM_SRC		= src/Bluejay.asm

ASM_INC		= 								\
			$(LAYOUTS:%=src/Layouts/%.inc)	\
			$(OMP_LAYOUTS:%=src/Layouts/%.inc) \
			src/Layouts/Base.inc			\
			src/BLHeliBootLoad.inc			\
			src/Silabs/SI_EFM8BB1_Defs.inc	\
			src/Silabs/SI_EFM8BB2_Defs.inc	\
			src/Silabs/SI_EFM8BB51_Defs.inc	\
			src/Silabs/SI_EFM8LB1_Defs.inc	\
			src/Modules/Common.asm			\
			src/Modules/Commutation.asm		\
			src/Modules/DShot.asm			\
			src/Modules/Eeprom.asm			\
			src/Modules/Fx.asm				\
			src/Modules/Isrs.asm			\
			src/Modules/Macros.asm			\
			src/Modules/Power.asm			\
			src/Modules/Scheduler.asm		\
			src/Modules/Settings.asm		\
			src/Modules/Timing.asm

# Check that wine/simplicity studio is available
EXECUTABLES	= $(AX51_BIN) $(LX51_BIN) $(OX51_BIN)
DUMMYVAR	:= $(foreach exec, $(EXECUTABLES), \
				$(if $(wildcard $(exec)),found, \
				$(error "Could not find $(exec). Make sure to set the correct paths to the simplicity install location")))

# Set up efm8load
EFM8_LOAD_BIN	?= tools/efm8load.py
EFM8_LOAD_PORT	?= /dev/ttyUSB0
EFM8_LOAD_BAUD	?= 115200

# Delete object files on error and warnings
.DELETE_ON_ERROR:

# AX51 mixes up input defines when run in parallel. Maybe because you cannot change the TMP directory per invocation.
.NOTPARALLEL:

define MAKE_OBJ
OBJS += $(1)_$(2)_$(3)_$(4)_$(VERSION).OBJ
$(OUTPUT_DIR)/$(1)_$(2)_$(3)_$(4)_$(VERSION).OBJ : $(ASM_SRC) $(ASM_INC)
	$(eval _ESC			:= $(1))
	$(eval _ESCNO		:= $(ESCNO_$(1)))
	$(if $(_ESCNO),,$(error Unknown layout identifier: $(1)))

	$(eval _MCU_TYPE	:= $(subst L,0,$(subst H,1,$(subst X,2,$(2)))))
	$(eval _DEADTIME	:= $(3))
	$(eval _PWM_FREQ	:= $(subst 24,0,$(subst 48,1,$(subst 96,2,$(4)))))
	$$(eval _LST		:= $$(patsubst %.OBJ,%.LST,$$@))
	@mkdir -p $(OUTPUT_DIR)
	@echo "AX51 : $$@"
	@$(AX51) $(ASM_SRC) \
		"DEFINE(ESCNO=$(_ESCNO)) " \
		"DEFINE(MCU_TYPE=$(_MCU_TYPE)) "\
		"DEFINE(DEADTIME=$(_DEADTIME)) "\
		"DEFINE(PWM_FREQ=$(_PWM_FREQ)) "\
		"OBJECT($$@) "\
		"PRINT($$(_LST)) "\
		"$(AX51_FLAGS)" > /dev/null 2>&1 || (grep -B 3 -E "\*\*\* (ERROR|WARNING)" $$(_LST); exit 1)
endef

SINGLE_TARGET_HEX = $(HEX_DIR)/$(LAYOUT)_$(MCU)_$(DEADTIME)_$(PWM)_$(VERSION).hex
OMP_TARGET_HEX = $(HEX_DIR)/X_H_5_24_$(VERSION).hex

single_target : $(SINGLE_TARGET_HEX)

# Create all obj targets using macro expansion
$(foreach _l, $(LAYOUTS), \
	$(foreach _m, $(MCUS), \
		$(foreach _d, $(DEADTIMES), \
			$(foreach _p, $(filter-out $(subst L,96,$(_m)), $(PWM_FREQS)), \
				$(eval $(call MAKE_OBJ,$(_l),$(_m),$(_d),$(_p)))))))

$(foreach _l, $(LAYOUTS_X), \
	$(foreach _m, $(MCUS_X), \
		$(foreach _d, $(DEADTIMES), \
			$(foreach _p, $(filter-out $(subst L,96,$(_m)), $(PWM_FREQS)), \
				$(eval $(call MAKE_OBJ,$(_l),$(_m),$(_d),$(_p)))))))

$(foreach _l, $(OMP_LAYOUTS), \
	$(foreach _m, $(OMP_MCUS), \
		$(foreach _d, $(OMP_DEADTIMES), \
			$(foreach _p, $(PWM_FREQS), \
				$(eval $(call MAKE_OBJ,$(_l),$(_m),$(_d),$(_p)))))))

HEX_TARGETS = $(OBJS:%.OBJ=$(HEX_DIR)/%.hex)

all : $(HEX_TARGETS)
	@echo "\nbuild finished. built $(shell ls -Aq $(HEX_DIR) | wc -l) hex targets\n"

# Conservative first-power build for the custom EFM8BB21 + FD6288 board.
omp: $(OMP_TARGET_HEX)

$(OUTPUT_DIR)/%.OMF : $(OUTPUT_DIR)/%.OBJ
	$(eval MAP := $(OUTPUT_DIR)/$(shell echo $(basename $(notdir $@)).MAP | tr 'a-z' 'A-Z'))
	@echo "LX51 : linking $< to $@"
#	Linking should produce exactly 1 warning
	@$(LX51) "$<" TO "$@" "$(LX51_FLAGS)" > /dev/null 2>&1; \
		test $$? -lt 2 && grep -q "1 WARNING" $(MAP) || \
		(grep -A 3 -E "\*\*\* (ERROR|WARNING)" $(MAP); exit 1)

$(HEX_DIR)/%.hex : $(OUTPUT_DIR)/%.OMF
	@mkdir -p $(HEX_DIR)
	@echo "OHX  : generating hex file $@"
	@$(OX51) "$<" "HEXFILE ($@)" > /dev/null 2>&1 || (echo "Error: Could not make hex file"; exit 1)

# Check if most recent commit changes production code (hex output)
check_commit: $(SINGLE_TARGET_HEX)
	@mv $(SINGLE_TARGET_HEX) $(SINGLE_TARGET_HEX:.hex=_after.hex)
	@git checkout HEAD~1
	@make $(SINGLE_TARGET_HEX)
	@git checkout -
	@diff $(SINGLE_TARGET_HEX) $(SINGLE_TARGET_HEX:.hex=_after.hex)

changelog:
	@npx -q mathiasvr/generate-changelog --exclude build,chore,ci,docs,refactor,style,other

help:
	@echo ""
	@echo "Usage examples"
	@echo "================================================================"
	@echo "make all                                 # Build all targets"
	@echo "make LAYOUT=A MCU=H DEADTIME=5 PWM=24    # Build a single target"
	@echo "make omp                                 # Build X_H_5_24 for the OMP ESC"
	@echo

clean:
	@rm -f $(OUTPUT_DIR)/*.{OBJ,MAP,OMF,LST}

efm8load: single_target
	$(EFM8_LOAD_BIN) -p $(EFM8_LOAD_PORT) -b $(EFM8_LOAD_BAUD) -w $(SINGLE_TARGET_HEX)

.PHONY: single_target all omp changelog help clean efm8load check_commit
