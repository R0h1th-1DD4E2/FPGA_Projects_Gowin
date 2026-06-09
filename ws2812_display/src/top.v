module ws2812_top(
    input  clk,
    input  reset_btn,
    output dout
);

    // --------------------------------------------------
    // PLL
    // --------------------------------------------------
    wire pll_lock;
    wire clk_20m;
    wire [7:0] mdrdo_unused;

    Gowin_PLL_MOD pll_inst (
        .lock    (pll_lock),
        .clkout0 (clk_20m),
        .mdrdo   (mdrdo_unused),
        .clkin   (clk),
        .reset   (reset_btn),
        .mdclk   (1'b0),
        .mdopc   (2'b00),
        .mdainc  (1'b0),
        .mdwdi   (8'b0)
    );

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    wire rst;

    assign rst = reset_btn; // | ~pll_lock;

    // --------------------------------------------------
    // Driver interface
    // --------------------------------------------------
    reg        valid;
    reg [23:0] pixel_val;
    reg        frame_done;

    wire ready;

    // --------------------------------------------------
    // Test pattern FSM
    // --------------------------------------------------
    localparam IDLE   = 3'd0;
    localparam PIX0   = 3'd1;
    localparam PIX1   = 3'd2;
    localparam DONE   = 3'd3;
    localparam WAIT_R = 3'd4;

    reg [2:0] state;

    always @(posedge clk_20m or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            valid      <= 1'b0;
            frame_done <= 1'b0;
            pixel_val  <= 24'h0;
        end
        else begin

            valid      <= 1'b0;
            frame_done <= 1'b0;

            case(state)

                //--------------------------------------------------
                // wait until driver ready
                //--------------------------------------------------
                IDLE: begin
                    if (ready)
                        state <= PIX0;
                end

                //--------------------------------------------------
                // LED0 = Green
                //--------------------------------------------------
                PIX0: begin
                    valid     <= 1'b1;
                    pixel_val <= 24'h200000; // GRB

                    if (ready)
                        state <= PIX1;
                end

                //--------------------------------------------------
                // LED1 = Red
                //--------------------------------------------------
                PIX1: begin
                    valid     <= 1'b1;
                    pixel_val <= 24'h002000; // GRB

                    if (ready)
                        state <= DONE;
                end

                //--------------------------------------------------
                // end of frame
                //--------------------------------------------------
                DONE: begin
                    frame_done <= 1'b1;
                    state <= WAIT_R;
                end

                //--------------------------------------------------
                // wait for driver to finish reset pulse
                //--------------------------------------------------
                WAIT_R: begin
                    if (ready)
                        state <= PIX0;
                end

            endcase
        end
    end

    // --------------------------------------------------
    // Existing driver
    // --------------------------------------------------
    led_driver drv_inst (
        .clk        (clk_20m),
        .rst        (rst),
        .valid      (valid),
        .frame_done (frame_done),
        .pixel_val  (pixel_val),
        .dout       (dout),
        .ready      (ready)
    );

endmodule