ifneq ($(MAKECMDGOALS),clean)
    # Yescrypt makes liberal use of GCC preprocessor and C extensions that
    # Microsoft's compiler doesn't support  (#warning, restrict, etc.). Clang
    # supports them, but is generally brittle for the options we need across
    # platforms, so we prefer GCC everywhere.

    # LLVM's OMP has a simpler license (MIT) than GNU's GOMP (GPL), but as long
    # as we're using GCC in the normal way linking GOMP falls under the GCC
    # Runtime Library Exception. See
    # https://www.gnu.org/licenses/gcc-exception-3.1-faq.en.html. Static and
    # dynamic linking are treated equally here.
    ifndef OMP_PATH
        $(warning WARNING: OMP_PATH not set, linker may not be able to find OpenMP)
    else
        OMP_PATH = -L"$(OMP_PATH)"
    endif
endif

SRC_DIR = src/yescrypt
BUILD_DIR = build
TARGET_DIR = src/pyescrypt
OBJS = $(BUILD_DIR)/yescrypt-opt.o $(BUILD_DIR)/yescrypt-common.o \
       $(BUILD_DIR)/sha256.o $(BUILD_DIR)/insecure_memzero.o

PLATFORM =
ifeq ($(OS),Windows_NT)
    PLATFORM = Windows
else
    UNAME := $(shell uname)
    ifeq ($(UNAME),Darwin)
        PLATFORM = macOS
    else
        PLATFORM = Linux
    endif
endif

ifeq ($(PLATFORM),Windows)
    ARCH = x86_64
else
    ARCH := $(shell uname -m)
endif

# Note: On macOS for ARM, this builds using a brew-installed version of clang.
# The system clang lacks support for OpenMP. `brew install llvm`, then run, for
# example, `make static CC=/opt/homebrew/opt/llvm/bin/clang`. v17.0.6 is known
# to work.
ifndef COMPILER
    $(warning WARNING: COMPILER not set, Make may not be able to find the compiler)
    COMPILER = gcc
    ifeq ($(PLATFORM),macOS)
        ifeq ($(ARCH),arm64)
            COMPILER = /opt/homebrew/opt/llvm/bin/clang
        endif
    endif
endif

ifeq ($(PLATFORM),Windows)
    CLEANUP = del /f /Q "$(BUILD_DIR)\*"
else
    CLEANUP = rm -f $(OBJS)
endif

SIMD =
ifeq ($(PLATFORM),macOS)
    ifeq ($(ARCH),x86_64)
        SIMD = -msse2
    endif
else
    SIMD = -mavx
endif

OMP = 
ifeq ($(PLATFORM),Windows)
    OMP = -static -lgomp
else ifeq ($(PLATFORM),macOS)
	OMP = -static -lgomp
else
    # Ubuntu ships with non-fPIC GOMP, so passing `-l:libgomp.a` fails. This is
    # generally fine, since the only missing GOMP we've seen on Linux is Amazon's
    # Python 3.8 Lambda runtime.
    OMP = -lgomp
endif

# Link GOMP statically when we can since it's not distributed with most systems.
.PHONY: static
static: $(OBJS)
	$(COMPILER) -shared -fPIC $(OBJS) $(OMP_PATH) -fopenmp $(OMP) -o $(TARGET_DIR)/yescrypt.bin

.PHONY: dynamic
dynamic: $(OBJS)
	$(COMPILER) -shared -fPIC $(OBJS) $(OMP_PATH) -fopenmp -o $(TARGET_DIR)/yescrypt.bin

# Note: DSKIP_MEMZERO isn't actually used (the code only has a SKIP_MEMZERO
# guard), but we retain it in case it's used later.
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(COMPILER) -Wall -O2 -fPIC -funroll-loops -fomit-frame-pointer -fopenmp -DSKIP_MEMZERO $(SIMD) -c $< -o $@

$(BUILD_DIR):
	mkdir $@

yescrypt-opt.o: $(SRC_DIR)/yescrypt-platform.c

.PHONY: clean
clean:
	- $(CLEANUP)
	rm -f $(TARGET_DIR)/yescrypt.bin
