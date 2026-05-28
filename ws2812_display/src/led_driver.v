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
reg frame_end_latch;
reg buf0_valid, buf1_valid;
reg [9:0] timer_cnt;
reg [4:0] t_h_cnt, t_l_cnt; // TODO: kept an extra bit for overflow, will be tested and removed 

wire buf_ready;
wire [23:0] buffer_out;
wire cur_bit;

localparam RESET=2'b00, SEND_H=2'b01, SEND_L=2'b11, HOLD_L=2'b10;

// Clock period is 20Mhz => 50ns, Hence the counts
localparam T0H = 7, T1H = 14, T0L = 16, T1L = 12, RES = 1023;

// Valid Ready handshake 
// valid flag to know if buffer ready after reset, read and frame done
always @(posedge clk or posedge rst) begin
    if (rst) begin
        buf0_valid <= 1'b0;    
        buf1_valid <= 1'b0;   
    end
    // when buf_ready != 1 and after first store
    else if (ready && valid)
        case (pix_sel)
                1'b0 : buf0_valid <= 1'b1;
                1'b1 : buf1_valid <= 1'b1; 
        endcase
    // reset of valid flags when one pixel is done
    else if (cur_state == SEND_L && timer_cnt == t_l_cnt && bit_cnt == 0) begin
        case (!pix_sel)
                1'b0 : buf0_valid <= 1'b0;
                1'b1 : buf1_valid <= 1'b0; 
        endcase
    end
    // reset of buffer valid flags when frame is done
    else if (frame_end_latch) begin
        buf0_valid <= 1'b0;    
        buf1_valid <= 1'b0;   
    end
    else begin
       buf0_valid <= buf0_valid;
       buf1_valid <= buf1_valid; 
    end
end

assign buf_ready = buf0_valid && buf1_valid;
assign buffer_out = (!pix_sel) ? pix_buf0 : pix_buf1;

// store buffer
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pix_buf0 <= 24'b0;
        pix_buf1 <= 24'b0;
        pix_sel <= 1'b0;
        ready <= 1'b1;
    end
    else begin
        if (valid && ready) begin
            case (pix_sel)
                1'b0 : pix_buf0 <= pixel_val;
                1'b1 : pix_buf1 <= pixel_val; 
            endcase
            pix_sel <= ~pix_sel;
        end
        if (!buf_ready) begin
            ready <= 1'b1;
        end
        else begin
            ready <= 1'b0;
        end
    end 
end

// Latch incoming frame_done pulse
always @(posedge clk or posedge rst) begin
    if (rst)
        frame_end_latch <= 1'b0;
    else if (frame_done)
        frame_end_latch <= 1'b1;
    else if (cur_state == RESET)
        frame_end_latch <= 1'b0;
end

// state update logic
always @(posedge clk or posedge rst) begin
    if (rst)
        cur_state <= RESET;
    else
        cur_state <= next_state;
end

assign cur_bit = buffer_out[bit_cnt]; // MSB first, bit_cnt is reverse counter

// Based on cur_bit the count for T_H and T_L
always @(*) begin
    if (cur_bit) begin
        t_h_cnt = T1H;
        t_l_cnt = T1L;
    end
    else begin
        t_h_cnt = T0H;
        t_l_cnt = T0L;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        timer_cnt <= 0;

    // reset timer whenever state changes
    else if (cur_state != next_state)
        timer_cnt <= 0;

    // count while staying inside same state
    else
        timer_cnt <= timer_cnt + 1;
end

// next state logic
always @(*) begin
    if (rst)
        next_state = RESET;
    else
        case (cur_state)
            RESET: next_state = (buf_ready) ? SEND_H : RESET;
            SEND_H: next_state = (timer_cnt == t_h_cnt) ? SEND_L : SEND_H;
            SEND_L: begin
                if (timer_cnt == t_l_cnt) begin
                    if (bit_cnt == 0)
                        next_state = (frame_end_latch) ? HOLD_L : SEND_H; 
                    else
                        next_state = SEND_H;
                end
                else
                    next_state = SEND_L;
            end
            HOLD_L: next_state = (timer_cnt == RES) ? RESET : HOLD_L;
            default: next_state = RESET;
        endcase
end

// bit counter
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

// output logic
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
