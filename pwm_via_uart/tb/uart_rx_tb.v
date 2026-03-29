module uart_rx_tb ();
    parameter CLK_PERIOD = 13020;     // 76.8KHz clock
    parameter BAUD_PERIOD = 104166;  // 9600 baud = 104.166us period
    
    // Testbench signals
    reg clk_uart = 0;
    reg rst;
    reg uart_rx;
    reg data_rcv;
    wire valid;
    wire [7:0] data;
    
    // Test data storage
    reg [7:0] test_data [0:3];
    reg [7:0] received_data [0:3];
    reg [3:0] test_case;
    reg [3:0] pass_count = 0;
    reg valid_d = 0;
    
    // Instantiate the receiver
    uart_rx uut (
        .clk_uart(clk_uart),
        .rst(rst),
        .uart_rx(uart_rx),
        .data_rcv(data_rcv),
        .rx_done(valid),
        .data(data)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk_uart = ~clk_uart;
    
    // Monitor valid signal
    always @(posedge clk_uart) begin
        valid_d <= valid;

        if (valid && !valid_d) begin
            received_data[test_case-1] = data;
            $display("Test Case %0d: Received 0x%h", test_case, data);
            
            if (data === test_data[test_case-1]) begin
                $display("✓ Test Case %0d Passed", test_case);
                pass_count = pass_count + 1;
            end else begin
                $display("✗ Test Case %0d Failed: Expected 0x%h, Got 0x%h", 
                          test_case, test_data[test_case-1], data);
            end
        end
    end
    
    // Task to send a byte over UART
    task send_byte;
        input [7:0] byte_to_send;
        integer i;
        begin
            // Start bit
            uart_rx = 0;
            #BAUD_PERIOD;
            
            // Data bits (LSB first_n)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = byte_to_send[i];
                #BAUD_PERIOD;
            end
            
            // Stop bit
            uart_rx = 1;
            #BAUD_PERIOD;
            
            // Extra time between bytes
            #(BAUD_PERIOD/2);
            data_rcv = 1; // Indicate data received from other block to comfirm hand shake
            #(BAUD_PERIOD/2);
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize test data
        test_data[0] = 8'h55; // Alternating 1s and 0s
        test_data[1] = 8'hFF; // All 1s
        test_data[2] = 8'h00; // All 0s
        test_data[3] = 8'h39; // Random pattern
        
        // Initialize signals
        rst = 1;
        uart_rx = 1;
        test_case = 0;
        
        // Apply reset
        #100;
        rst = 0;
        #100;
        
        // Test Case 1: 0x55
        test_case = 1;
        $display("\nTest Case %0d: Sending 0x%h (Alternating bits)", test_case, test_data[test_case-1]);
        send_byte(test_data[test_case-1]);
        #(BAUD_PERIOD*2);
        
        // Test Case 2: 0xFF
        test_case = 2;
        $display("\nTest Case %0d: Sending 0x%h (All ones)", test_case, test_data[test_case-1]);
        send_byte(test_data[test_case-1]);
        #(BAUD_PERIOD*2);
        
        // Test Case 3: 0x00
        test_case = 3;
        $display("\nTest Case %0d: Sending 0x%h (All zeros)", test_case, test_data[test_case-1]);
        send_byte(test_data[test_case-1]);
        #(BAUD_PERIOD*2);
        
        // Test Case 4: 0x39
        test_case = 4;
        $display("\nTest Case %0d: Sending 0x%h (Mixed pattern)", test_case, test_data[test_case-1]);
        send_byte(test_data[test_case-1]);
        #(BAUD_PERIOD*2);
        
        // Test report
        $display("\n----- Test Summary -----");
        $display("Passed: %0d out of 4 tests", pass_count);
        if (pass_count == 4)
            $display("All tests PASSED!");
        else
            $display("Some tests FAILED!");
            
        // End simulation
        $display("Simulation completed");
        $finish;
    end

    initial begin
        $dumpfile("uart_rx_tb.vcd");
        $dumpvars(0, uart_rx_tb);
    end

endmodule