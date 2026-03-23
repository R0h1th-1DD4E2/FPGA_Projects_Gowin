// pwm_gen.v module 
// Generates PWM signal based on the data 
// received from uart_rx module
// wait sfor the data_en signal to be high to update threshold value
// data_rcv signal is used to ack the uart_rx module 
// of successfull handshake 

module pwm_gen (
    input wire pwm_clk,
    input wire rst,
    input wire [7:0] data,
    input wire data_en,
    output reg pwm_out,
    output reg data_rcv
);

    reg [7:0] counter;
    reg [7:0] threshold;

    always @(posedge pwm_clk or posedge rst) begin
        if (rst) begin
            counter <= 'b0;
            pwm_out <= 'b0;
            threshold <= 'b0;
            data_rcv <= 'b0;
        end
        else begin
            if (data_en) begin
                threshold <= data;
                data_rcv <= 'b1;
            end
            else begin
                data_rcv <= 'b0;
            end

            if (counter < threshold) begin
                pwm_out <= 1'b1;
            end
            else begin
                pwm_out <= 1'b0;
            end

            counter <= counter + 1'b1;
        end
    end

endmodule