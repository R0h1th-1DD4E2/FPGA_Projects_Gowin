# Primary clock 
create_clock -name clk_50m -period 20.000 [get_ports {clk}]

# Internal generated clocks from clock_gen
create_generated_clock -name clk_uart -source [get_ports {clk}] -divide_by 1302 [get_nets {clk_uart_Z}]
create_generated_clock -name clk_pwm  -source [get_ports {clk}] -divide_by 3906 [get_nets {clk_pwm_Z}]
