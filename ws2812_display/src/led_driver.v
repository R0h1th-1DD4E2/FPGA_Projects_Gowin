// WS2812 driver 
// Needs GRB 24 bit format to drive the output
// Handshake - Ready Valid Type 
// A valid handshake drives data out port 
// Includes Ping Pong buffer for the pixel data
// State machine to drive the output

module led_driver(
    input clk, 
    input rst,
    input valid,
    input frame_done,
    input [23:0] pixel_val,
    output reg dout,            // drives the led
    output reg ready
);

reg [23:0] pix_buf0, pix_buf1;
reg [4:0] bit_cnt;
reg pix_sel;
reg [2:0] next_state, cur_state;
reg frame_pending;
reg buf0_valid, buf1_valid;

wire buf_ready;
wire [23:0] buffer_out;
wire cur_bit, next_bit;

localparam RESET=2'b00, SEND_H=2'b01, SEND_L=2'b11, HOLD_L=2'b10

// Valid Ready handshake 
// sticky bit to know if buffer ready after reset 
always @(posedge clk or posedge rst) begin
    if (rst) begin
        buf0_valid <= 1'b0;    
        buf1_valid <= 1'b0;   
    end
    else if (ready && valid) // when buf_ready != 1 and after first store
        case (pix_sel)
                1'b0 : buf0_valid <= 1'b1;
                1'b1 : buf1_valid <= 1'b1; 
        endcase
    else begin
       buf0_valid <= buf0_valid;
       buf1_valid <= buf1_valid; 
    end
end

assign buf_ready = buf0_valid && buf1_valid;
assign buffer_out = (!pix_sel ) ? pix_buf0 : pix_buf1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pix_buf0 <= 24'b0;
        pix_buf1 <= 24'b0;
        pix_sel <= 1'b0;
    end
    else begin
        if (valid && ready) begin
            case (pix_sel)
                1'b0 : pix_buf0 <= pixel_val;
                1'b1 : pix_buf1 <= pixel_val; 
            endcase
            pix_sel <= ~pix_sel;
        end
    end 
end

// Latch incoming frame_done pulse
always @(posedge clk or posedge rst) begin
    if (rst)
        frame_pending <= 1'b0;
    else if (frame_done)
        frame_pending <= 1'b1;
    else if (cur_state == START_FRAME)
        frame_pending <= 1'b0;
end

// state update logic
always @(posedge clk or posedge rst) begin
    if (rst)
        cur_state <= RESET;
    else
        cur_state <= next_state;
end

wire cur_bit = buffer_out[23 - bit_cnt]; // MSB first
wire next_bit = buffer_out[23 - (bit_cnt + 1)]; // has overflow bit_cnt == 23, but at that situation, change pix_sel

// next state logic
always @(*) begin
    if (rst)
        next_state <= RESET;
    else
        case (cur_state)
            RESET: next_state <= (buf_ready) ? SEND_H : RESET;
            SEND_H: next_state <= SEND_L;
            SEND_L: next_state <= (frame_pending) ? HOLD_L : RESET;
            HOLD_L: next_state <= RESET;
        endcase
end

// output logic
always @(*) begin
    
end

endmodule
