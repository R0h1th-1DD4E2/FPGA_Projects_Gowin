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

// -------------------------
// Registers
// -------------------------
reg [23:0] pix_buf0, pix_buf1;
reg [4:0]  bit_cnt;
reg [2:0]  next_state, cur_state;
reg        frame_end_latch;
reg [9:0]  timer_cnt;
reg [4:0]  t_h_cnt, t_l_cnt;   // TODO: kept an extra bit for overflow, will be tested and removed
reg [1:0]  fill_cnt;
reg        wr_ptr, rd_ptr;

// -------------------------
// Wires
// -------------------------
wire        full, empty;
wire        buf_ready, buf_avlb;
wire [23:0] buffer_out;
wire        cur_bit;
wire        pixel_done;

// -------------------------
// State encoding
// -------------------------
localparam RESET=2'b00, SEND_H=2'b01, SEND_L=2'b11, HOLD_L=2'b10;

// Clock period is 20MHz => 50ns, Hence the counts
localparam T0H = 7, T1H = 14, T0L = 16, T1L = 12, RES = 1023;

// -------------------------
// FIFO — full/empty flags
// -------------------------
assign full      = (fill_cnt == 2'd2);
assign empty     = (fill_cnt == 2'd0);
assign buf_ready = full;
assign buf_avlb  = !empty;

// -------------------------
// Buffer read mux
// -------------------------
assign buffer_out = rd_ptr ? pix_buf1 : pix_buf0;
assign cur_bit    = buffer_out[bit_cnt];   // MSB first, bit_cnt is reverse counter

// -------------------------
// Pixel done strobe
// -------------------------
assign pixel_done = (cur_state == SEND_L) && (timer_cnt == t_l_cnt) && (bit_cnt == 0);

// -------------------------
// Buffer write
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pix_buf0 <= 24'b0;
        pix_buf1 <= 24'b0;
    end else if (valid && ready) begin
        case (wr_ptr)
            1'b0: pix_buf0 <= pixel_val;
            1'b1: pix_buf1 <= pixel_val;
        endcase
    end
end

// -------------------------
// FIFO control — fill_cnt, pointers, ready
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst) begin
        fill_cnt <= 2'd0;
        wr_ptr    <= 1'b0;
        rd_ptr    <= 1'b0;
        ready     <= 1'b1;
    end else begin

        // fill_cnt counter
        case ({valid && ready, pixel_done})
            2'b10:   fill_cnt <= fill_cnt + 1'b1;
            2'b01:   fill_cnt <= fill_cnt - 1'b1;
            default: fill_cnt <= fill_cnt;
        endcase

        // Write pointer
        if (valid && ready)
            wr_ptr <= ~wr_ptr;

        // Read pointer
        if (pixel_done)
            rd_ptr <= ~rd_ptr;

        // Frame flush — on HOLD_L entry only
        if (cur_state != HOLD_L && next_state == HOLD_L) begin
            fill_cnt <= 2'd0;
            wr_ptr    <= 1'b0;
            rd_ptr    <= 1'b0;
        end

        ready <= !full;
    end
end

// -------------------------
// Latch incoming frame_done pulse
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        frame_end_latch <= 1'b0;
    else if (frame_done)
        frame_end_latch <= 1'b1;
    else if (cur_state == HOLD_L)
        frame_end_latch <= 1'b0;
end

// -------------------------
// State update
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        cur_state <= RESET;
    else
        cur_state <= next_state;
end

// -------------------------
// T_H / T_L counts based on current bit
// -------------------------
always @(*) begin
    if (cur_bit) begin
        t_h_cnt = T1H - 1;
        t_l_cnt = T1L - 1;
    end else begin
        t_h_cnt = T0H - 1;
        t_l_cnt = T0L - 1;
    end
end

// -------------------------
// Timer — resets on state change
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        timer_cnt <= 0;
    else if (cur_state != next_state)
        timer_cnt <= 0;
    else
        timer_cnt <= timer_cnt + 1;
end

// -------------------------
// Next state logic
// -------------------------
always @(*) begin
    if (rst)
        next_state = RESET;
    else
        case (cur_state)
            RESET:  next_state = (buf_ready) ? SEND_H : RESET;
            SEND_H: next_state = (timer_cnt == t_h_cnt) ? SEND_L : SEND_H;
            SEND_L: begin
                if (timer_cnt == t_l_cnt) begin
                    if (bit_cnt == 0)
                        next_state = (frame_end_latch || !buf_avlb) ? HOLD_L : SEND_H;
                    else
                        next_state = SEND_H;
                end else
                    next_state = SEND_L;
            end
            HOLD_L:  next_state = (timer_cnt == RES) ? RESET : HOLD_L;
            default: next_state = RESET;
        endcase
end

// -------------------------
// Bit counter
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        bit_cnt <= 23;
    else if (cur_state == SEND_L && (next_state == SEND_H || next_state == HOLD_L)) begin
        if (bit_cnt == 0)
            bit_cnt <= 23;
        else
            bit_cnt <= bit_cnt - 1;
    end
end

// -------------------------
// Output logic
// -------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        dout <= 1'b0;
    else begin
        case (cur_state)
            RESET:  dout <= 1'b0;
            SEND_H: dout <= 1'b1;
            SEND_L: dout <= 1'b0;
            HOLD_L: dout <= 1'b0;
        endcase
    end
end

endmodule