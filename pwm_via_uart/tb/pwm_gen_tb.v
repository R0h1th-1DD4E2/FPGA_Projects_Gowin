module pwm_gen_tb ();

    reg pwm_clk;
    reg rst;
    reg [7:0] data;
    reg data_en;
    wire pwm_out;
    wire data_rcv;

    pwm_gen uut (
        .pwm_clk(pwm_clk),
        .rst(rst),
        .data(data),
        .data_en(data_en),
        .pwm_out(pwm_out),
        .data_rcv(data_rcv)
    );

    initial begin
        // Initialize signals
        pwm_clk = 0;
        rst = 1;
        data = 8'b00000000;
        data_en = 0;

        #10000 rst = 0;

        // Test case 1: Set threshold to 128 (50% duty cycle)
        #10 data = 8'b10000000;
            data_en = 1;
        #10 data_en = 0;
        #10000;

        // Test case 2: Set threshold to 64 (25% duty cycle)
        #10 data = 8'b01000000;
            data_en = 1;
        #10 data_en = 0;
        #10000;

        // Test case 3: Set threshold to 192 (75% duty cycle)
        #10 data = 8'b11000000;
            data_en = 1;
        #10 data_en = 0;
        #10000;

        #100 $finish;
    end

    always #5 pwm_clk = ~pwm_clk;

    initial begin
        $dumpfile("pwm_gen_tb.vcd");
        $dumpvars(0, pwm_gen_tb);
    end
    
endmodule