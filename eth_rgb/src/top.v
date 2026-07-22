module ws2812_top(
    input  clk,
    input  reset_btn,
    output dout,
    output clk_e
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

    assign clk_e = clk_20m;

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    wire rst;
    assign rst = reset_btn;

    // --------------------------------------------------
    // Driver interface
    // --------------------------------------------------
    reg        valid;
    reg [23:0] pixel_val;
    reg        frame_done;

    wire ready;

    // --------------------------------------------------
    // Smooth color wheel
    // --------------------------------------------------
    reg [17:0] color_cnt;
    reg [7:0]  r, g, b;
    reg [2:0]  phase;

    always @(posedge clk_20m or posedge rst) begin
        if (rst) begin
            color_cnt <= 18'd0;
            phase     <= 3'd0;

            r <= 8'hFF;
            g <= 8'h00;
            b <= 8'h00;
        end
        else begin

            if (color_cnt == 18'd100000) begin
                color_cnt <= 18'd0;

                case (phase)

                    // Red -> Yellow
                    3'd0: begin
                        if (g == 8'hFF)
                            phase <= 3'd1;
                        else
                            g <= g + 1'b1;
                    end

                    // Yellow -> Green
                    3'd1: begin
                        if (r == 8'h00)
                            phase <= 3'd2;
                        else
                            r <= r - 1'b1;
                    end

                    // Green -> Cyan
                    3'd2: begin
                        if (b == 8'hFF)
                            phase <= 3'd3;
                        else
                            b <= b + 1'b1;
                    end

                    // Cyan -> Blue
                    3'd3: begin
                        if (g == 8'h00)
                            phase <= 3'd4;
                        else
                            g <= g - 1'b1;
                    end

                    // Blue -> Magenta
                    3'd4: begin
                        if (r == 8'hFF)
                            phase <= 3'd5;
                        else
                            r <= r + 1'b1;
                    end

                    // Magenta -> Red
                    3'd5: begin
                        if (b == 8'h00)
                            phase <= 3'd0;
                        else
                            b <= b - 1'b1;
                    end

                endcase
            end
            else begin
                color_cnt <= color_cnt + 1'b1;
            end
        end
    end

    // --------------------------------------------------
    // Test pattern FSM
    // --------------------------------------------------
    localparam IDLE   = 2'd0;
    localparam PIXEL  = 2'd1;
    localparam DONE   = 2'd2;
    localparam WAIT_R = 2'd3;

    reg [1:0] state;

    always @(posedge clk_20m or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            valid      <= 1'b0;
            frame_done <= 1'b0;
            pixel_val  <= 24'h000000;
        end
        else begin

            valid      <= 1'b0;
            frame_done <= 1'b0;

            case(state)

                //------------------------------------------
                // Wait until driver ready
                //------------------------------------------
                IDLE: begin
                    if (ready)
                        state <= PIXEL;
                end

                //------------------------------------------
                // Send color wheel value
                //------------------------------------------
                PIXEL: begin
                    valid     <= 1'b1;
                    pixel_val <= {g, r, b}; // GRB format

                    if (ready)
                        state <= DONE;
                end

                //------------------------------------------
                // End frame
                //------------------------------------------
                DONE: begin
                    frame_done <= 1'b1;
                    state <= WAIT_R;
                end

                //------------------------------------------
                // Wait for reset pulse completion
                //------------------------------------------
                WAIT_R: begin
                    if (ready)
                        state <= PIXEL;
                end

                default: begin
                    state <= IDLE;
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