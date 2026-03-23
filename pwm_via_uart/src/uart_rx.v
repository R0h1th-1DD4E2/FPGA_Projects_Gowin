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
    localparam IDLE = 3'b000, START = 3'b001, DATA = 3'b010, STOP = 3'b011, DONE = 3'b100, OVR_SAMP = 3'b101;

    reg [2:0] oversampling_counter;
    reg [2:0] bit_counter;

    reg [2:0] next_state, cur_state;
    reg [2:0] prev_state; // Sampling state reference to determine state transition
    reg [7:0] sample;

    wire majority;

    assign majority = (sample[3] & sample[4]) | (sample[4] & sample[5]) | (sample[3] & sample[5]);

    always @(posedge clk_uart or posedge rst) begin
        if (rst) begin
            next_state <= IDLE;
            cur_state <= IDLE;
        end
        else
            cur_state <= next_state;
    end

    always @(posedge clk_uart or posedge rst) begin
        if (rst) begin
            prev_state <= IDLE;
        end
        else if (next_state != cur_state) begin
            prev_state <= cur_state;
        end
        else begin
            prev_state <= prev_state;
        end
    end

    always @(*) begin
        case (cur_state)
            IDLE: next_state <= (!uart_rx) ? START : IDLE;
            START: next_state <= (oversampling_counter == 3'b111) ? DATA : START;
            DATA: next_state <= OVR_SAMP;
            STOP: next_state <= OVR_SAMP;
            DONE: next_state <= (data_rcv) ? IDLE : DONE;
            OVR_SAMP: begin
                case (prev_state)
                    START: next_state <= (oversampling_counter == 3'b111) ? ((!majority) ? DATA : IDLE) : OVR_SAMP;
                    DATA: next_state <= (oversampling_counter == 3'b111) ? ((bit_counter == 3'b111) ? STOP : DATA) : OVR_SAMP;
                    STOP: next_state <= (oversampling_counter == 3'b111) ? DONE : OVR_SAMP;
                    default: begin
                        next_state <= OVR_SAMP;
                    end
                endcase
            end
            default: next_state <= IDLE;
        endcase
    end

    always @(*) begin
        case (cur_state)
            IDLE : begin
                rx_done <= 'b0;
                data <= 'b0;
                sample <= 'b0;
                oversampling_counter <= 'b0;
                bit_counter <= 'b0;
            end
            START : begin
                rx_done <= 'b0;
                data <= 'b0;
                sample <= 'b0;
            end
            DATA : begin
                rx_done <= 'b0;
                sample <= 'b0;
                data[bit_counter] <= majority;
            end
            STOP : begin
                rx_done <= 'b0;
                data <= data;
            end
            DONE : begin
                rx_done <= 'b1;
                data <= data;
            end
            OVR_SAMP : begin
                {bit_counter, oversampling_counter} = oversampling_counter + 1'b1;
                sample[oversampling_counter] <= uart_rx;
            end
            default: begin
                default_case
            end
        endcase
    end

endmodule