// uart_rx.v module is a uart reciever 
// with no error detection
// Has oversampling of 8 
// Runs on 78600 Hz clock
// 8 bit : data, none : parity, 1 bit : stop bit 
// rst clear any stuck state transition

module uart_rx (
    input wire clk_uart,
    input wire rst,
    input wire uart_rx,
    input wire data_rcv,
    output reg rx_done,
    output reg [7:0] data
);
    localparam IDLE = 3'b000, START = 3'b001, DATA = 3'b010, STOP = 3'b011, DONE = 3'b100;

    reg [2:0] cur_state;
    reg [2:0] sample_counter;
    reg [2:0] bit_counter;
    reg [7:0] sample;

    wire majority;

    assign majority = (sample[3] & sample[4]) | (sample[4] & sample[5]) | (sample[3] & sample[5]);

    always @(posedge clk_uart or posedge rst) begin
        if (rst) begin
            cur_state <= IDLE;
            sample_counter <= 3'b000;
            bit_counter <= 3'b000;
            sample <= 8'b00000000;
            data <= 8'b00000000;
            rx_done <= 1'b0;
        end
        else begin
            rx_done <= 1'b0;

            case (cur_state)
                IDLE: begin
                    sample_counter <= 3'b000;
                    bit_counter <= 3'b000;
                    sample <= 8'b00000000;

                    if (!uart_rx)
                        cur_state <= START;
                end

                START: begin
                    sample[sample_counter] <= uart_rx;

                    if (sample_counter == 3'b111) begin
                        sample_counter <= 3'b000;
                        if (!majority)
                            cur_state <= DATA;
                        else
                            cur_state <= IDLE;
                    end
                    else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                DATA: begin
                    sample[sample_counter] <= uart_rx;

                    if (sample_counter == 3'b111) begin
                        sample_counter <= 3'b000;
                        data[bit_counter] <= majority;

                        if (bit_counter == 3'b111) begin
                            bit_counter <= 3'b000;
                            cur_state <= STOP;
                        end
                        else begin
                            bit_counter <= bit_counter + 1'b1;
                        end
                    end
                    else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                STOP: begin
                    sample[sample_counter] <= uart_rx;

                    if (sample_counter == 3'b111) begin
                        sample_counter <= 3'b000;
                        if (majority)
                            cur_state <= DONE;
                        else
                            cur_state <= IDLE;
                    end
                    else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end

                DONE: begin
                    rx_done <= 1'b1;
                    if (data_rcv)
                        cur_state <= IDLE;
                end

                default: begin
                    cur_state <= IDLE;
                end
            endcase
        end
    end

endmodule