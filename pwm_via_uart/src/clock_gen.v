// clock_gen.v module generates clock signal 
// for pwm generator and uart_reciever.
// Input clock is 50MHz
// Output clock for pwm is 25600 Hz and 
// Output clock for uart is 76800 Hz (for baud rate 9600 with oversampling 8)

module clock_gen (
    input wire clk_50mhz,
    input wire rst,
    output reg clk_pwm,
    output reg clk_uart
);

    // UART: Divider = F_clk / (Baud * Oversample) = 50MHz / (9600 * 8)
    localparam UART_DIVIDER = 326; 

    // PWM: Scalar = F_clk / (F_cycle * 2^n) = 50MHz / (100 * 256)
    localparam PWM_SCALAR = 977;

    // why not $clog2(UART_DIVIDER) - 1? 
    // need 10 bits which is 9:0 and not 8:0
    reg [$clog2(UART_DIVIDER):0] uart_counter;
    reg [$clog2(PWM_SCALAR):0] pwm_counter;

    always @(posedge clk_50mhz or posedge rst) begin
        if (rst) begin
            uart_counter <= 'b0;
            clk_uart <= 'b0;
        end
        else if (uart_counter == UART_DIVIDER - 1) begin
            uart_counter <= 'b0;
            clk_uart <= ~clk_uart;
        end
        else begin
            uart_counter <= uart_counter + 1'b1;
        end
    end

    always @(posedge clk_50mhz or posedge rst) begin
        if (rst) begin
           pwm_counter <= 'b0;
           clk_pwm <= 'b0; 
        end
        else if (pwm_counter == PWM_SCALAR - 1) begin
            pwm_counter <= 'b0;
            clk_pwm <= ~clk_pwm;
        end
        else begin
            pwm_counter <= pwm_counter + 1'b1;
        end
    end
    
endmodule