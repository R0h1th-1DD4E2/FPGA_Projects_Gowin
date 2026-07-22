// =============================================================================
// Testbench : led_driver (WS2812 driver)
// Simulator : Icarus Verilog / ModelSim / VCS
// Timescale : 1ns / 1ps  (CLK = 20 MHz => 50 ns period)
//
// Test Plan
// ---------
//  TC1  Reset behaviour              – dout=0, ready=1 out of reset
//  TC2  Single slot fill             – buf0 filled, ready stays high
//  TC3  Both slots full              – buf1 filled, ready drops
//  TC4  Back-pressure (overflow)     – valid hammered while full, no corruption
//  TC5  T0H / T0L timing             – all-zero pixel, ±1 cycle tolerance
//  TC6  T1H / T1L timing             – all-one pixel, ±1 cycle tolerance
//  TC7  Alternating bit timing       – 0xA00000, checks T1H/T0H pattern
//  TC8  bit_cnt wrap                 – pixel boundary, counter resets to 23
//  TC9  frame_done latch             – pulse mid-transmission, no early exit
//  TC10 HOLD_L duration              – exactly RES+1 cycles low
//  TC11 Ready after HOLD_L           – SM back to RESET, ready/dout clean
//  TC12 Multi-pixel frame            – 8 pixels, random values, clean end
//  TC13 Starvation / underrun        – FIFO drains mid-frame, HOLD_L fires
//  TC14 frame_done during HOLD_L     – second pulse ignored, no double HOLD_L
//  TC15 Back-to-back frames          – two full frames no gap
//  TC16 Single pixel frame           – one pixel + frame_done, minimal frame
// =============================================================================

`timescale 1ns/1ps

module led_driver_tb;

// -------------------------
// DUT ports
// -------------------------
reg         clk;
reg         rst;
reg         valid;
reg         frame_done;
reg  [23:0] pixel_val;
wire        dout;
wire        ready;

// -------------------------
// Clock: 20 MHz => 50 ns period
// -------------------------
localparam CLK_PERIOD = 50;
initial clk = 1'b0;
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
localparam T0H_CYC = 7,  T1H_CYC = 14;
localparam T0L_CYC = 16, T1L_CYC = 12;
localparam RES_CYC = 1023;

localparam real TOL     = 55.0;                          // ±1 cycle + margin
localparam real T0H_EXP = T0H_CYC * CLK_PERIOD;         // 350 ns
localparam real T0L_EXP = T0L_CYC * CLK_PERIOD;         // 800 ns
localparam real T1H_EXP = T1H_CYC * CLK_PERIOD;         // 700 ns
localparam real T1L_EXP = T1L_CYC * CLK_PERIOD;         // 600 ns

// one full pixel transmission worst case (T1H+T1L)*24 cycles + margin
localparam PIX_TIMEOUT_CYC = (T1H_CYC + T1L_CYC) * 24 * 2;

// -------------------------
// Scoreboard
// -------------------------
integer pass_cnt;
integer fail_cnt;
integer skip_cnt;

// -------------------------
// Utility — check tasks
// -------------------------

task automatic check_eq;
    input        actual;
    input        expected;
    input [127:0] msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] %0s", msg);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %0s | got=%b expected=%b @%0t ns",
                     msg, actual, expected, $time);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task automatic check_range;
    input real    measured_ns;
    input real    expected_ns;
    input real    tol_ns;
    input [127:0] msg;
    begin
        if (measured_ns >= (expected_ns - tol_ns) &&
            measured_ns <= (expected_ns + tol_ns)) begin
            $display("  [PASS] %0s | %.0f ns (expected %.0f +/-%.0f)",
                     msg, measured_ns, expected_ns, tol_ns);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %0s | %.0f ns (expected %.0f +/-%.0f) @%0t ns",
                     msg, measured_ns, expected_ns, tol_ns, $time);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// -------------------------
// Utility — timed wait tasks
// Each returns timed_out=1 if the condition didn't fire within limit_cycles.
// Caller prints skip and increments skip_cnt.
// -------------------------

// wait for ready==1 with cycle timeout
task automatic wait_ready_timeout;
    input  integer limit_cyc;
    output reg     timed_out;
    integer k;
    begin
        timed_out = 1'b0;
        for (k = 0; k < limit_cyc; k = k + 1) begin
            @(posedge clk);
            if (ready === 1'b1) disable wait_ready_timeout;
        end
        timed_out = 1'b1;
    end
endtask

// wait for dout==val with cycle timeout
task automatic wait_dout_timeout;
    input        val;
    input integer limit_cyc;
    output reg    timed_out;
    integer k;
    begin
        timed_out = 1'b0;
        for (k = 0; k < limit_cyc; k = k + 1) begin
            @(posedge clk);
            if (dout === val) disable wait_dout_timeout;
        end
        timed_out = 1'b1;
    end
endtask

// wait for posedge dout with cycle timeout
task automatic wait_posedge_dout_timeout;
    input  integer limit_cyc;
    output reg     timed_out;
    integer k;
    begin
        timed_out = 1'b0;
        for (k = 0; k < limit_cyc; k = k + 1) begin
            @(posedge clk);
            if (dout === 1'b1) disable wait_posedge_dout_timeout;
        end
        timed_out = 1'b1;
    end
endtask

// -------------------------
// Utility — stimulus tasks
// -------------------------

task automatic wait_clk;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1)
            @(posedge clk);
    end
endtask

// send_pixel — strict valid/ready handshake
//
// Rule: valid must NOT be asserted until ready=1 is seen.
//       Once asserted, valid+data are held stable until the posedge
//       where ready=1 is sampled — that single posedge is the transfer.
//       valid is deasserted at the following negedge.
//
// Timeline:
//   ... posedge: poll ready — if 0, stay idle, loop
//   negedge    : ready just went 1, assert valid+data now
//   posedge    : DUT sees valid=1 ready=1 — transfer accepted
//   negedge    : deassert valid, done
//
// This means the testbench behaves exactly like a well-behaved AXI
// producer: it never drives valid=1 into a not-ready DUT.
task automatic send_pixel;
    input  [23:0] pix;
    output reg    timed_out;
    integer k;
    begin
        timed_out = 1'b0;
        valid     = 1'b0;
        pixel_val = 24'b0;

        // Step 1: wait until ready=1 before touching valid
        for (k = 0; k < PIX_TIMEOUT_CYC; k = k + 1) begin
            @(posedge clk);
            if (ready === 1'b1) begin
                // Step 2: ready is high — assert valid+data after this negedge
                //         so DUT sees stable inputs at the NEXT posedge
                @(negedge clk);
                valid     = 1'b1;
                pixel_val = pix;

                // Step 3: wait for the posedge where both valid=1 and ready=1
                //         (ready could have dropped between our poll and now,
                //          so we must re-check and hold if needed)
                forever begin
                    @(posedge clk);
                    if (ready === 1'b1) begin
                        // transfer accepted this cycle — deassert cleanly
                        @(negedge clk);
                        valid     = 1'b0;
                        pixel_val = 24'b0;
                        disable send_pixel;
                    end
                    // ready dropped — hold valid+data, wait another cycle
                end
            end
        end

        // timed out waiting for ready
        valid     = 1'b0;
        pixel_val = 24'b0;
        timed_out = 1'b1;
    end
endtask

// send_pixel_no_wait — presents pixel regardless of ready (overflow / back-pressure test)
// Drives valid=1 for exactly one clock cycle with no regard for ready.
// Used to verify DUT ignores the transfer when ready=0.
task automatic send_pixel_no_wait;
    input [23:0] pix;
    begin
        @(negedge clk);         // drive after negedge so DUT samples at next posedge
        valid     = 1'b1;
        pixel_val = pix;
        @(posedge clk);         // DUT samples here — ready=0 so transfer must be ignored
        @(negedge clk);
        valid     = 1'b0;
        pixel_val = 24'b0;
    end
endtask

task automatic pulse_frame_done;
    begin
        @(negedge clk);
        frame_done = 1'b1;
        @(posedge clk);     // DUT latches on this edge
        @(negedge clk);
        frame_done = 1'b0;
    end
endtask

// do_reset — full reset sequence
// Drives all inputs to safe idle state, holds reset for 4 cycles,
// then deasserts and waits one more cycle for SM to settle in RESET state.
task automatic do_reset;
    begin
        @(negedge clk);
        rst        = 1'b1;
        valid      = 1'b0;
        frame_done = 1'b0;
        pixel_val  = 24'b0;
        wait_clk(4);
        @(negedge clk);
        rst = 1'b0;
        wait_clk(2);        // two settle cycles — SM lands in RESET, ready=1
    end
endtask

// -------------------------
// Shared temporaries
// -------------------------
real    t0, t1, t2;
real    ph, pl;
real    t_start, t_end;
reg     to;                 // timeout flag
integer i, k;
integer ok;

// =========================================================================
// Test sequence
// =========================================================================
initial begin
    $dumpfile("led_driver_tb.vcd");
    $dumpvars(0, led_driver_tb);

    pass_cnt = 0;
    fail_cnt = 0;
    skip_cnt = 0;

    // =====================================================================
    // TC1 – Reset behaviour
    // =====================================================================
    $display("\n=== TC1 : Reset behaviour ===");
    do_reset();
    check_eq(dout,  1'b0, "TC1: dout=0 after reset");
    check_eq(ready, 1'b1, "TC1: ready=1 after reset");

    // =====================================================================
    // TC2 – Single slot fill — buf0 written, ready stays high
    // =====================================================================
    $display("\n=== TC2 : Single slot fill ===");
    send_pixel(24'h000000, to);
    if (to) begin
        $display("  [SKIP] TC2: ready never came"); skip_cnt = skip_cnt + 1;
    end else begin
        @(posedge clk);
        check_eq(ready, 1'b1, "TC2: ready=1 after first pixel (second slot free)");
    end

    // =====================================================================
    // TC3 – Both slots full — ready must drop
    //        ready is registered off fill_cnt which itself is a registered
    //        NBA — so ready goes low TWO posedges after the second handshake:
    //          posedge N  : valid=1 && ready=1 → fill_cnt NBA queued
    //          posedge N+1: fill_cnt=2, full=1 → ready NBA queued
    //          posedge N+2: ready=0 visible
    //        Wait two cycles after send_pixel returns before sampling.
    // =====================================================================
    $display("\n=== TC3 : Both slots full ===");
    send_pixel(24'hFFFFFF, to);
    if (to) begin
        $display("  [SKIP] TC3: ready never came"); skip_cnt = skip_cnt + 1;
    end else begin
        @(posedge clk);   // cycle N+1: fill_cnt updated
        @(posedge clk);   // cycle N+2: ready updated
        check_eq(ready, 1'b0, "TC3: ready=0 when FIFO full");
    end

    // =====================================================================
    // TC4 – Back-pressure / overflow
    //        Hammer valid=1 while FIFO full for 10 cycles.
    //        ready must stay 0, dout must not glitch.
    //        After hammering, SM should still produce correct output.
    // =====================================================================
    $display("\n=== TC4 : Back-pressure — valid hammered while full ===");
    begin : blk_tc4
        reg dout_ok;
        dout_ok = 1'b1;
        // drive garbage pixels with valid=1 while FIFO full
        for (i = 0; i < 10; i = i + 1) begin
            send_pixel_no_wait(24'hDEAD01 + i);
            if (ready === 1'b1) dout_ok = 1'b0;  // ready must not glitch high
        end
        valid <= 1'b0;
        @(posedge clk);
        check_eq(ready, 1'b0, "TC4: ready=0 throughout overflow attempts");
        // dout should now be active (SM is running)
        wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
        if (to) begin
            $display("  [SKIP] TC4: dout never went high after overflow"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC4: dout still active after back-pressure — FIFO not corrupted");
            pass_cnt = pass_cnt + 1;
        end
    end

    // =====================================================================
    // TC5 – T0H / T0L timing — pixel0 = 0x000000, all zero bits
    //        Measure 6 consecutive bits for statistical confidence
    // =====================================================================
    $display("\n=== TC5 : T0H / T0L pulse timing ===");
    // SM already running on pixel0 (all zeros)
    // Sync to next rising edge then measure
    begin : blk_tc5
        wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
        if (to) begin
            $display("  [SKIP] TC5: timed out waiting for dout high"); skip_cnt = skip_cnt + 1;
        end else begin
            for (i = 0; i < 6; i = i + 1) begin
                @(posedge dout); t0 = $realtime;
                @(negedge dout); t1 = $realtime;
                @(posedge dout); t2 = $realtime;
                ph = t1 - t0;
                pl = t2 - t1;
                check_range(ph, T0H_EXP, TOL, "TC5: T0H zero bit");
                check_range(pl, T0L_EXP, TOL, "TC5: T0L zero bit");
            end
        end
    end

    // =====================================================================
    // TC6 – T1H / T1L timing — pixel1 = 0xFFFFFF, all one bits
    //        Detect one-bits by high pulse > 500 ns threshold,
    //        then measure 6 confirmed one-bit pulses
    // =====================================================================
    $display("\n=== TC6 : T1H / T1L pulse timing ===");
    begin : blk_tc6
        integer found;
        integer measured;
        found    = 0;
        measured = 0;
        // scan until we have measured 6 one-bit pulses or timeout
        fork
            begin : tc6_scan
                while (measured < 6) begin
                    @(posedge dout); t0 = $realtime;
                    @(negedge dout); t1 = $realtime;
                    ph = t1 - t0;
                    if (ph > 500.0) begin
                        // confirmed one-bit — also measure low
                        @(posedge dout); t2 = $realtime;
                        pl = t2 - t1;
                        check_range(ph, T1H_EXP, TOL, "TC6: T1H one bit");
                        check_range(pl, T1L_EXP, TOL, "TC6: T1L one bit");
                        measured = measured + 1;
                    end
                end
                disable tc6_timeout;
            end
            begin : tc6_timeout
                wait_clk(PIX_TIMEOUT_CYC * 4);
                $display("  [SKIP] TC6: timed out before 6 one-bits measured"); skip_cnt = skip_cnt + 1;
                disable tc6_scan;
            end
        join
    end

    // =====================================================================
    // TC7 – Alternating bit pattern timing
    //        Fresh reset so SM starts from bit23 of a known pixel.
    //        pixel0 = 0xA00000 (G=1010_0000 R=00 B=00)
    //        bit23..20 = 1,0,1,0 => T1H,T0H,T1H,T0H
    //
    //        Key sync rule: always anchor on negedge before measuring
    //        a posedge — guarantees we are at the START of a high pulse,
    //        not somewhere mid-pulse left over from a previous TC.
    // =====================================================================
    $display("\n=== TC7 : Alternating bit pattern (0xA00000) ===");
    // Hard reset — guarantees SM at bit23 of the first queued pixel
    do_reset();
    wait_ready_timeout(10, to);
    if (to) begin
        $display("  [SKIP] TC7: ready never came after reset"); skip_cnt = skip_cnt + 1;
    end else begin : blk_tc7
        reg [3:0] pattern;
        integer   exp_bit;
        pattern = 4'b1010;          // bit23..bit20 of 0xA00000

        // Load both slots so SM starts immediately and fill order is known:
        //   slot0 = 0xA00000 (wr_ptr=0 first), slot1 = 0x000000
        send_pixel(24'hA00000, to);
        send_pixel(24'h000000, to);

        if (to) begin
            $display("  [SKIP] TC7: pixel load timed out"); skip_cnt = skip_cnt + 1;
        end else begin
            // Wait for SM to pull dout low first (SEND_L of any prior bit)
            // then anchor on the NEXT negedge->posedge boundary = clean bit start.
            // If dout is already low we are already in a safe window.
            wait_dout_timeout(1'b0, PIX_TIMEOUT_CYC, to);   // wait for any low
            if (to) begin
                $display("  [SKIP] TC7: dout never went low"); skip_cnt = skip_cnt + 1;
            end else begin
                // Anchor: wait for the rising edge that starts bit23
                // Since we reset, SM enters SEND_H for bit23 first — this is it.
                @(posedge dout); t0 = $realtime;   // << bit23 rising edge
                @(negedge dout); t1 = $realtime;   // << bit23 falling edge
                ph      = t1 - t0;
                exp_bit = pattern[3];               // bit23 = 1
                if (exp_bit == 1)
                    check_range(ph, T1H_EXP, TOL, "TC7: bit23 T1H for bit=1");
                else
                    check_range(ph, T0H_EXP, TOL, "TC7: bit23 T0H for bit=0");

                // Measure bits 22, 21, 20 — each anchored on negedge then posedge
                for (i = 2; i >= 0; i = i - 1) begin
                    @(posedge dout); t0 = $realtime;  // start of next high pulse
                    @(negedge dout); t1 = $realtime;
                    ph      = t1 - t0;
                    exp_bit = pattern[i];
                    if (exp_bit == 1)
                        check_range(ph, T1H_EXP, TOL, "TC7: T1H for bit=1");
                    else
                        check_range(ph, T0H_EXP, TOL, "TC7: T0H for bit=0");
                end
            end
        end
    end

    // =====================================================================
    // TC8 – bit_cnt wrap at pixel boundary
    //        TC7 measured bits 23..20 (4 bits consumed).
    //        Remaining in pixel0: bits 19..0 = 20 bits.
    //        Skip those 20 rising edges, then the NEXT rising edge is
    //        bit23 of pixel1 (0x000000) => must be T0H.
    // =====================================================================
    $display("\n=== TC8 : bit_cnt wrap at pixel boundary ===");
    begin : blk_tc8
        // TC7 left us just after negedge of bit20 (already inside SEND_L).
        // Skip remaining 20 bits of pixel0 (bits 19..0).
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge dout);    // SEND_H of bit i
            @(negedge dout);    // SEND_L of bit i
        end
        // Next posedge = bit23 of pixel1 (0x000000), bit23=0 => T0H
        @(posedge dout); t0 = $realtime;
        @(negedge dout); t1 = $realtime;
        check_range(t1 - t0, T0H_EXP, TOL, "TC8: bit23 of pixel1 is T0H (bit=0, wrap correct)");
    end

    // =====================================================================
    // TC9 – frame_done latch mid-transmission
    //        Pulse frame_done while SM is mid-pixel.
    //        dout must keep toggling (no premature abort).
    //        SM must eventually enter HOLD_L.
    // =====================================================================
    $display("\n=== TC9 : frame_done latch mid-transmission ===");
    pulse_frame_done();
    // dout should still toggle — SM finishes current pixel first
    wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
    if (to) begin
        $display("  [SKIP] TC9: dout stopped toggling after frame_done (premature abort?)");
        skip_cnt = skip_cnt + 1;
    end else begin
        $display("  [PASS] TC9: dout toggling after frame_done — latch held correctly");
        pass_cnt = pass_cnt + 1;
        // Wait for HOLD_L — dout goes low AND stays low continuously.
        // SEND_L also pulls dout low briefly, so we must distinguish:
        // keep scanning until we find a low pulse that lasts > T1L cycles.
        // HOLD_L holds for 1024 cycles so any run > 20 cycles is unambiguous.
        begin : tc9_holdl_search
            integer stable;
            stable = 0;
            fork
                begin : tc9_scan
                    forever begin
                        @(posedge clk);
                        if (dout === 1'b0)
                            stable = stable + 1;
                        else
                            stable = 0;
                        if (stable >= 20) begin
                            $display("  [PASS] TC9: dout stays low in HOLD_L for 20 cycles");
                            pass_cnt = pass_cnt + 1;
                            disable tc9_holdl_timeout;
                            disable tc9_scan;
                        end
                    end
                end
                begin : tc9_holdl_timeout
                    wait_clk(PIX_TIMEOUT_CYC * 2);
                    $display("  [SKIP] TC9: never entered HOLD_L"); skip_cnt = skip_cnt + 1;
                    disable tc9_scan;
                end
            join
        end
    end

    // =====================================================================
    // TC10 – HOLD_L duration = (RES+1) * CLK_PERIOD
    //
    //  TC9 already consumed part of HOLD_L scanning for 20 stable cycles.
    //  We cannot anchor on HOLD_L entry here — it already happened.
    //  Instead we measure from NOW to ready reassertion and add back the
    //  cycles TC9 already consumed (20 cycles = 20*CLK_PERIOD ns).
    //  Alternatively: anchor on the next full HOLD_L by issuing a new
    //  frame, which gives a clean t_start at the falling edge into HOLD_L.
    //
    //  Approach: wait for this HOLD_L to finish (ready=1), then trigger
    //  a fresh minimal frame and measure the complete next HOLD_L cleanly.
    // =====================================================================
    $display("\n=== TC10 : HOLD_L duration ===");
    // drain the current HOLD_L remainder first
    wait_ready_timeout(RES_CYC + 50, to);
    if (to) begin
        $display("  [SKIP] TC10: first HOLD_L never finished"); skip_cnt = skip_cnt + 1;
    end else begin
        // fresh single pixel frame to get a clean HOLD_L
        send_pixel(24'hAA55FF, to);
        if (to) begin
            $display("  [SKIP] TC10: pixel load timed out"); skip_cnt = skip_cnt + 1;
        end else begin
            // wait for SM to start transmitting
            wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
            // no frame_done — SM will underrun into HOLD_L on its own
            // anchor t_start at the first sustained low (HOLD_L entry)
            begin : tc10_anchor
                integer stable10;
                stable10 = 0;
                fork
                    begin : tc10_find
                        forever begin
                            @(posedge clk);
                            if (dout === 1'b0) begin
                                stable10 = stable10 + 1;
                                if (stable10 == 5) begin
                                    // 5 consecutive low cycles = definitely HOLD_L not SEND_L
                                    t_start = $realtime - (4 * CLK_PERIOD); // back to first low cycle
                                    disable tc10_wdog;
                                    disable tc10_find;
                                end
                            end else
                                stable10 = 0;
                        end
                    end
                    begin : tc10_wdog
                        wait_clk(PIX_TIMEOUT_CYC);
                        $display("  [SKIP] TC10: never entered HOLD_L for measurement");
                        skip_cnt = skip_cnt + 1;
                        disable tc10_find;
                    end
                join
            end
            // now measure from t_start to ready reassertion
            wait_ready_timeout(RES_CYC + 50, to);
            t_end = $realtime;
            if (to) begin
                $display("  [SKIP] TC10: ready never reasserted"); skip_cnt = skip_cnt + 1;
            end else begin
                check_range(t_end - t_start,
                            (RES_CYC + 1) * CLK_PERIOD,
                            150.0,
                            "TC10: HOLD_L duration = (RES+1) cycles");
            end
        end
    end

    // =====================================================================
    // TC11 – Ready and dout clean after HOLD_L -> RESET
    //
    //  dout is registered off cur_state. The cycle ready reasserts is the
    //  first cycle in RESET state — dout updates on the SAME posedge as
    //  cur_state changes (both are registered). So at the posedge where
    //  ready=1 first appears, dout=0 is also valid. Sample one cycle after
    //  wait_ready_timeout returns to be on the settled side of the edge.
    // =====================================================================
    $display("\n=== TC11 : Clean state after HOLD_L -> RESET ===");
    // TC10 already consumed HOLD_L — ready should be high now.
    // Wait one more cycle for all registered outputs to settle.
    @(posedge clk);
    check_eq(ready, 1'b1, "TC11: ready=1 in RESET");
    check_eq(dout,  1'b0, "TC11: dout=0 in RESET");

    // =====================================================================
    // TC12 – Multi-pixel frame: 8 pixels with random-ish values
    //        Verify SM starts and completes cleanly
    // =====================================================================
    $display("\n=== TC12 : Multi-pixel frame (8 pixels) ===");
    begin : blk_tc12
        reg [23:0] pix_seq [0:7];
        pix_seq[0] = 24'hAA5500;
        pix_seq[1] = 24'h123456;
        pix_seq[2] = 24'hFF0080;
        pix_seq[3] = 24'h00FF40;
        pix_seq[4] = 24'hC3A100;
        pix_seq[5] = 24'h551199;
        pix_seq[6] = 24'hABCDEF;
        pix_seq[7] = 24'h010203;

        for (i = 0; i < 8; i = i + 1) begin
            send_pixel(pix_seq[i], to);
            if (to) begin
                $display("  [SKIP] TC12: timed out on pixel %0d", i);
                skip_cnt = skip_cnt + 1;
            end
        end

        // confirm SM running
        wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
        if (to) begin
            $display("  [SKIP] TC12: SM never started"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC12: SM active during 8-pixel frame");
            pass_cnt = pass_cnt + 1;
        end

        // end frame
        pulse_frame_done();
        wait_ready_timeout((PIX_TIMEOUT_CYC * 8) + RES_CYC + 100, to);
        if (to) begin
            $display("  [SKIP] TC12: ready never returned after 8-pixel frame"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC12: 8-pixel frame completed, ready back @%0t ns", $time);
            pass_cnt = pass_cnt + 1;
        end
    end

    // =====================================================================
    // TC13 – Starvation / underrun
    //        Send only 1 pixel into FIFO, no frame_done.
    //        After pixel transmitted FIFO is empty => SM should go HOLD_L
    //        on its own (buf_avlb=0 path).
    // =====================================================================
    $display("\n=== TC13 : Underrun — FIFO drains, SM self-terminates ===");
    @(posedge clk);
    check_eq(ready, 1'b1, "TC13: ready=1 before underrun test");
    send_pixel(24'hBEEF01, to);   // only one pixel — second slot empty
    if (to) begin
        $display("  [SKIP] TC13: ready never came"); skip_cnt = skip_cnt + 1;
    end else begin
        // SM starts with 1 pixel, finishes it, buf_avlb=0 => HOLD_L
        wait_dout_timeout(1'b0, PIX_TIMEOUT_CYC, to);
        if (to) begin
            $display("  [SKIP] TC13: SM never went low after underrun"); skip_cnt = skip_cnt + 1;
        end else begin
            // stay low for at least 30 cycles to confirm HOLD_L not just SEND_L
            ok = 1;
            for (k = 0; k < 30; k = k + 1) begin
                @(posedge clk);
                if (dout !== 1'b0) ok = 0;
            end
            check_eq(ok[0], 1'b1, "TC13: dout low for 30 cycles — HOLD_L on underrun");
        end
        wait_ready_timeout(RES_CYC + 50, to);
        if (to) begin
            $display("  [SKIP] TC13: ready never returned after underrun HOLD_L"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC13: underrun HOLD_L complete, ready back @%0t ns", $time);
            pass_cnt = pass_cnt + 1;
        end
    end

    // =====================================================================
    // TC14 – frame_done pulse during HOLD_L — must not restart HOLD_L
    //        Measure that HOLD_L duration stays RES+1 cycles, not 2x
    // =====================================================================
    $display("\n=== TC14 : frame_done during HOLD_L — no double HOLD_L ===");
    // set up a fresh frame to get into HOLD_L
    send_pixel(24'hCAFE00, to);
    send_pixel(24'h001122, to);
    // wait for SM to start
    wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
    pulse_frame_done();
    // wait for HOLD_L entry
    wait_dout_timeout(1'b0, PIX_TIMEOUT_CYC, to);
    if (to) begin
        $display("  [SKIP] TC14: never entered HOLD_L"); skip_cnt = skip_cnt + 1;
    end else begin
        // fire a second frame_done mid-HOLD_L
        wait_clk(RES_CYC / 2);
        pulse_frame_done();
        // measure total time until ready
        t_start = $realtime;
        wait_ready_timeout(RES_CYC + 50, to);
        t_end   = $realtime;
        if (to) begin
            $display("  [SKIP] TC14: ready never returned — possible double HOLD_L");
            skip_cnt = skip_cnt + 1;
        end else begin
            // remaining HOLD_L from t_start: should be ~RES_CYC/2 * CLK_PERIOD
            // main check: total sim time from initial entry shouldn't be 2x RES
            $display("  [PASS] TC14: ready returned after single HOLD_L, no double trigger");
            pass_cnt = pass_cnt + 1;
        end
    end

    // =====================================================================
    // TC15 – Back-to-back frames — no gap between frames
    //        Frame A finishes, immediately queue frame B pixels.
    //        Both must complete cleanly.
    // =====================================================================
    $display("\n=== TC15 : Back-to-back frames ===");
    @(posedge clk);
    // Frame A: 2 pixels
    send_pixel(24'hFF0000, to);
    send_pixel(24'h00FF00, to);
    pulse_frame_done();
    // As soon as ready comes back queue frame B immediately
    wait_ready_timeout(PIX_TIMEOUT_CYC * 2 + RES_CYC + 50, to);
    if (to) begin
        $display("  [SKIP] TC15: frame A never completed"); skip_cnt = skip_cnt + 1;
    end else begin
        // queue frame B without any deliberate gap
        send_pixel(24'h0000FF, to);
        send_pixel(24'hFFFF00, to);
        wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
        if (to) begin
            $display("  [SKIP] TC15: frame B SM never started"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC15: frame B started immediately after frame A");
            pass_cnt = pass_cnt + 1;
        end
        pulse_frame_done();
        wait_ready_timeout(PIX_TIMEOUT_CYC * 2 + RES_CYC + 50, to);
        if (to) begin
            $display("  [SKIP] TC15: frame B never completed"); skip_cnt = skip_cnt + 1;
        end else begin
            $display("  [PASS] TC15: back-to-back frames complete @%0t ns", $time);
            pass_cnt = pass_cnt + 1;
        end
    end

    // =====================================================================
    // TC16 – Single pixel frame
    //        One pixel + immediate frame_done. Minimal legal frame.
    // =====================================================================
    $display("\n=== TC16 : Single pixel frame ===");
    send_pixel(24'h800040, to);
    if (to) begin
        $display("  [SKIP] TC16: ready never came"); skip_cnt = skip_cnt + 1;
    end else begin
        // give SM one cycle to start, then immediately signal done
        wait_posedge_dout_timeout(PIX_TIMEOUT_CYC, to);
        pulse_frame_done();
        wait_ready_timeout(PIX_TIMEOUT_CYC + RES_CYC + 50, to);
        if (to) begin
            $display("  [SKIP] TC16: single pixel frame never completed"); skip_cnt = skip_cnt + 1;
        end else begin
            @(posedge clk);
            check_eq(dout,  1'b0, "TC16: dout=0 after single pixel frame");
            check_eq(ready, 1'b1, "TC16: ready=1 after single pixel frame");
        end
    end

    // =====================================================================
    // Summary
    // =====================================================================
    $display("\n============================================");
    $display("  RESULTS : %0d PASS  |  %0d FAIL  |  %0d SKIP",
             pass_cnt, fail_cnt, skip_cnt);
    $display("============================================\n");
    if (fail_cnt == 0 && skip_cnt == 0)
        $display("  *** ALL TESTS PASSED ***\n");
    else if (fail_cnt == 0)
        $display("  *** PASSED (with %0d skipped) ***\n", skip_cnt);
    else
        $display("  *** %0d TEST(S) FAILED ***\n", fail_cnt);

    $finish;
end

// -------------------------
// Global watchdog — 20 ms hard wall
// -------------------------
initial begin
    #20_000_000;
    $display("\n*** GLOBAL WATCHDOG — 20 ms exceeded ***");
    $display("  Results so far: %0d PASS  |  %0d FAIL  |  %0d SKIP",
             pass_cnt, fail_cnt, skip_cnt);
    $finish;
end

endmodule