// OV7670 Capture Module
// Captures pixel data from camera and stores in block RAM
module ov7670_capture (
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    output wire [16:0] addr,
    output wire [11:0] dout,
    output reg         we
);

    reg [15:0] d_latch = 16'h0000;
    reg [16:0] address = 17'h00000;
    reg [1:0]  line = 2'b00;
    reg [6:0]  href_last = 7'b0000000;
    reg        href_hold = 1'b0;
    reg        latched_vsync = 1'b0;
    reg        latched_href = 1'b0;
    reg [7:0]  latched_d = 8'h00;
    
    assign addr = address;
    assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};
    
    always @(posedge pclk) begin
        // Address increment
        if (we == 1'b1) begin
            address <= address + 1'b1;
        end
        
        // Detect rising edge on href - start of scan line
        if (href_hold == 1'b0 && latched_href == 1'b1) begin
            case (line)
                2'b00: line <= 2'b01;
                2'b01: line <= 2'b10;
                2'b10: line <= 2'b11;
                default: line <= 2'b00;
            endcase
        end
        href_hold <= latched_href;
        
        // Capture data from camera - RGB565 format
        if (latched_href == 1'b1) begin
            d_latch <= {d_latch[7:0], latched_d};
        end
        we <= 1'b0;
        
        // New frame detection
        if (latched_vsync == 1'b1) begin
            address <= 17'h00000;
            href_last <= 7'b0000000;
            line <= 2'b00;
        end else begin
            // Write enable control - capture every other line for 320x240
            if (href_last[2] == 1'b1) begin
                if (line[1] == 1'b1) begin
                    we <= 1'b1;
                end
                href_last <= 7'b0000000;
            end else begin
                href_last <= {href_last[5:0], latched_href};
            end
        end
    end
    
    // Latch inputs on falling edge
    always @(negedge pclk) begin
        latched_d <= d;
        latched_href <= href;
        latched_vsync <= vsync;
    end
    
endmodule

// Address Generator Module for VGA Display
module Address_Generator (
    input  wire        CLK25,
    input  wire        enable,
    input  wire        vsync,
    output wire [16:0] address
);

    reg [16:0] val = 17'h00000;
    
    assign address = val;
    
    always @(posedge CLK25) begin
        if (enable == 1'b1) begin
            // 320x240 = 76800 pixels
            if (val < 76800) begin
                val <= val + 1'b1;
            end
        end
        
        // Reset on vsync
        if (vsync == 1'b0) begin
            val <= 17'h00000;
        end
    end
    
endmodule