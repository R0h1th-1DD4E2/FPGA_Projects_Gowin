// top.v module 
// integrates uart_rx and pwm_gen modules
// uart_rx receives data from uart and sends it to pwm_gen
// pwm_gen generates pwm signal based on the data received from uart_rx
// when data is received from uart_rx, 
// uart module holds it value until pwm_gen module acknowledges

module top (
    input wire clk,
    input wire rst,
    input wire uart_rx,
    output wire pwm_out
);

    wire [7:0] data;
    wire data_en;
    wire data_rcv;
    wire clk_pwm;
    wire clk_uart;


    clock_gen clock_generator (
        .clk_50mhz(clk),
        .rst(rst),
        .clk_pwm(clk_pwm),
        .clk_uart(clk_uart)
    );

    uart_rx uart_receiver (
        .uart_rx(uart_rx),
        .rst(rst),
        .data(data),
        .rx_done(data_en),
        .data_rcv(data_rcv)
    );

    pwm_gen pwm_generator (
        .pwm_clk(clk_pwm),
        .rst(rst),
        .data(data),
        .data_en(data_en),
        .pwm_out(pwm_out),
        .data_rcv(data_rcv)
    );

endmodule