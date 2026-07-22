TESTBENCHES = led_driver
DIR := $(CURDIR)

all: $(TESTBENCHES)

$(TESTBENCHES):
	@echo "Running testbench: $@"
	mkdir -p output
	iverilog -o output/$@.out $@_tb.v ../src/$@.v
	cd output && vvp $@.out
	@echo "Testbench $@ completed."

dump:
	openFPGALoader -b tangprimer25k $(DIR)/../impl/pnr/ws2812_display.fs

dump_flash:
	openFPGALoader -b tangprimer25k -f $(DIR)/../impl/pnr/ws2812_display.fs

clean:
	rm -f output/*.out
