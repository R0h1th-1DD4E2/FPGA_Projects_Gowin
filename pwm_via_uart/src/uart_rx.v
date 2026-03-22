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
    
    reg [3:0] oversampling_counter;
    reg [3:0] bit_counter;

    reg [3:0] next_state, cur_state;
    reg [3:0] prev_state; // Sampling state reference to determine state transition

    localparam IDLE = 3'b000, START = 3'b001, DATA = 3'b010, STOP = 3'b011, DONE = 3'b100, OVR_SAMP = 3'b101;

    always @(posedge clk_50mhz or posedge rst) begin
        if (rst) begin
            next_state <= IDLE;
            cur_state <= IDLE;
        end
        else
            cur_state <= next_state;
    end

    always @(*) begin
        case (cur_state)
            IDLE: next_state <= (!uart_rx) ? OVR_SAMP : IDLE;
            START: next_state <= (oversampling_counter == 3'b111) ? DATA : START;
            IDLE: next_state <= (!uart_rx) ? START : IDLE;
            IDLE: next_state <= (!uart_rx) ? START : IDLE;
            OVR_SAMP: begin
                case (prev_state)
                    IDLE: next_state <= (oversampling_counter == 3'b111) ? ((!rx_input) ? START : IDLE) : OVR_SAMP;
                    START: next_state <= (oversampling_counter == 3'b111) ? DATA : OVR_SAMP;
                    DATA: next_state <= (oversampling_counter == 3'b111) ? ((bit_counter == 3'b111) ? STOP : DATA) : OVR_SAMP;
                    STOP: next_state <= (oversampling_counter == 3'b111) ? DONE : OVR_SAMP;
                    default: begin
                        next_state <= OVR_SAMP;
                    end
                endcase
            end
            default: 
        endcase
    end

endmodule