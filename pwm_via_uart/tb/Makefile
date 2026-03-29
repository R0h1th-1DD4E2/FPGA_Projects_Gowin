TESTBENCHES = pwm_gen uart_rx

all: $(TESTBENCHES)

$(TESTBENCHES):
	@echo "Running testbench: $@"
	mkdir -p output
	iverilog -o output/$@.out $@_tb.v ../src/$@.v
	cd output && vvp $@.out
	@echo "Testbench $@ completed."

clean:
	rm -f output/*.out