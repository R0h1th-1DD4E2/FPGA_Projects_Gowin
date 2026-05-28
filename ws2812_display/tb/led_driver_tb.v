// Testbench for WS2812 led_driver
// Tests:
//   1. Reset behaviour
//   2. Valid/Ready handshake and ping-pong buffer fill
//   3. Bit transmission timing (T0H, T0L, T1H, T1L)
//   4. bit_cnt decrement and pixel boundary
//   5. frame_done -> HOLD_L -> RESET flow

`timescale 1ns/1ps

module led_driver_tb;

// -------------------------
// DUT signals
// -------------------------
reg         clk;
reg         rst;
reg         valid;
reg         frame_done;
reg  [23:0] pixel_val;
wire        dout;
wire        ready;

// -------------------------
// Clock: 20MHz => 50ns period
// -------------------------
localparam CLK_PERIOD = 50;

always #(CLK_PERIOD/2) clk = ~clk;

// -------------------------
// DUT instantiation
// -------------------------
led_driver dut (
    .clk        (clk),
    .rst        (rst),
    .valid      (valid),
    .frame_done (frame_done),
    .pixel_val  (pixel_val),
    .dout       (dout),
    .ready      (ready)
);

// -------------------------
// Timing parameters (mirror RTL)
// -------------------------
localparam T0H = 7, T1H = 14, T0L = 16, T1L = 12, RES = 1023;

// -------------------------
// Helpers
// -------------------------
integer i;
integer pass_cnt, fail_cnt;

task send_pixel;
    input [23:0] pix;
    begin
        @(posedge clk);
        // wait for ready
        while (!ready) @(posedge clk);
        valid     <= 1'b1;
        pixel_val <= pix;
        @(posedge clk);
        valid     <= 1'b0;
        pixel_val <= 24'b0;
    end
endtask

task assert_eq;
    input       actual;
    input       expected;
    input [63:0] label;
    begin
        if (actual === expected) begin
            $display("  PASS : %s", label);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL : %s  got=%b expected=%b  @time=%0t", label, actual, expected, $time);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// -------------------------
// dout monitor — measure high/low pulse widths each bit
// -------------------------
real t_rise, t_fall, t_next_rise;
real t_high_ns, t_low_ns;
integer bit_index;

// -------------------------
// Test sequence
// -------------------------
initial begin
    $dumpfile("led_driver_tb.vcd");
    $dumpvars(0, led_driver_tb);

    clk        = 0;
    rst        = 1;
    valid      = 0;
    frame_done = 0;
    pixel_val  = 24'b0;
    pass_cnt   = 0;
    fail_cnt   = 0;

    // ------------------------------------------------
    // TEST 1: Reset — dout must be low, ready asserts
    // ------------------------------------------------
    $display("\n=== TEST 1: Reset ===");
    repeat(4) @(posedge clk);
    rst = 0;
    @(posedge clk);
    assert_eq(dout,  1'b0, "dout low after reset");
    assert_eq(ready, 1'b1, "ready high after reset");

    // ------------------------------------------------
    // TEST 2: Handshake — feed two pixels (fills ping-pong)
    //         ready should drop after both buffers full
    // ------------------------------------------------
    $display("\n=== TEST 2: Ping-pong buffer fill ===");

    // pixel 0 — all zeros (G=0 R=0 B=0)
    send_pixel(24'h000000);
    @(posedge clk);
    assert_eq(ready, 1'b1, "ready still high after first pixel (buf1 empty)");

    // pixel 1 — all ones (G=FF R=FF B=FF)
    send_pixel(24'hFFFFFF);
    // give one cycle for buf_ready to settle
    @(posedge clk);
    assert_eq(ready, 1'b0, "ready drops when both buffers full");
    #5000000
    // ------------------------------------------------
    // TEST 3: dout goes high once SM enters SEND_H
    // ------------------------------------------------
    $display("\n=== TEST 3: Transmission starts ===");
    // wait for SEND_H — dout should go high
    wait(dout === 1'b1);
    $display("  PASS : dout went high — SEND_H entered @%0t", $time);
    pass_cnt = pass_cnt + 1;

    // ------------------------------------------------
    // TEST 4: Bit timing check for first 4 bits of pixel0
    //         pixel0 = 24'h000000 so all bits are 0
    //         expect T0H=7 cycles high, T0L=16 cycles low
    // ------------------------------------------------
    $display("\n=== TEST 4: T0H / T0L timing for zero bits ===");
    repeat(4) begin : timing_loop
        // measure high pulse
        @(posedge dout);   t_rise      = $realtime;
        @(negedge dout);   t_fall      = $realtime;
        t_high_ns = t_fall - t_rise;

        // measure low pulse
        @(posedge dout);   t_next_rise = $realtime;
        t_low_ns  = t_next_rise - t_fall;

        // T0H=7 cycles *50ns=350ns, T0L=16*50=800ns
        // allow +-1 cycle tolerance (50ns)
        if (t_high_ns >= 300 && t_high_ns <= 400)
            $display("  PASS : T0H=%.0fns (expected ~350ns)", t_high_ns);
        else
            $display("  FAIL : T0H=%.0fns (expected ~350ns) @%0t", t_high_ns, $time);

        if (t_low_ns >= 750 && t_low_ns <= 850)
            $display("  PASS : T0L=%.0fns (expected ~800ns)", t_low_ns);
        else
            $display("  FAIL : T0L=%.0fns (expected ~800ns) @%0t", t_low_ns, $time);
    end

    // ------------------------------------------------
    // TEST 5: frame_done -> HOLD_L -> RESET
    //         send frame_done after pixel0 finishes
    //         (pixel1 = 0xFFFFFF will send, then HOLD_L)
    // ------------------------------------------------
    $display("\n=== TEST 5: frame_done and HOLD_L ===");
    // pulse frame_done — latch should catch it
    @(posedge clk);
    frame_done <= 1'b1;
    @(posedge clk);
    frame_done <= 1'b0;

    // wait for dout to go low and stay low for >RES cycles (HOLD_L)
    wait(dout === 1'b0);
    // sample dout after RES+10 cycles — should still be in HOLD_L then go RESET
    repeat(RES + 10) @(posedge clk);
    // after HOLD_L dout should be low and ready should reassert
    assert_eq(dout,  1'b0, "dout low during/after HOLD_L");

    // wait for ready to come back (SM back to RESET, buffers cleared)
    wait(ready === 1'b1);
    $display("  PASS : ready reasserted after HOLD_L -> RESET @%0t", $time);
    pass_cnt = pass_cnt + 1;

    // ------------------------------------------------
    // TEST 6: Second frame — 3 pixels, check bit_cnt
    //         wraps cleanly at pixel boundary
    // ------------------------------------------------
    $display("\n=== TEST 6: Multi-pixel second frame ===");
    send_pixel(24'hAA5500); // pixel A
    send_pixel(24'h123456); // pixel B

    // assert SM starts again
    wait(dout === 1'b1);
    $display("  PASS : second frame started @%0t", $time);
    pass_cnt = pass_cnt + 1;

    // send third pixel and frame_done together
    send_pixel(24'hFFFF00); // pixel C
    @(posedge clk);
    frame_done <= 1'b1;
    @(posedge clk);
    frame_done <= 1'b0;

    // wait for HOLD_L completion
    wait(ready === 1'b1);
    $display("  PASS : second frame completed, ready back @%0t", $time);
    pass_cnt = pass_cnt + 1;

    // ------------------------------------------------
    // Summary
    // ------------------------------------------------
    $display("\n===========================================");
    $display("  Results: %0d PASS  |  %0d FAIL", pass_cnt, fail_cnt);
    $display("===========================================\n");

    $finish;
end

// ------------------------------------------------
// Timeout watchdog — 5ms max
// ------------------------------------------------
initial begin
    #500_000_000;
    $display("TIMEOUT — simulation exceeded 5ms");
    $finish;
end

endmodule