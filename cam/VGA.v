// VGA Controller - 640x480 @ 60Hz with 25MHz pixel clock
module VGA (
    input  wire CLK25,         // 25 MHz clock input
    output wire clkout,        // Clock output to ADV7123 and TFT screen
    output reg  Hsync,         // Horizontal sync
    output reg  Vsync,         // Vertical sync
    output wire Nblank,        // Blanking signal for DAC
    output reg  activeArea,    // Active display area (320x240 window)
    output wire Nsync          // Sync signal for TFT
);

    // VGA timing parameters for 640x480 @ 60Hz
    parameter HM = 799;  // Total horizontal pixels - 1
    parameter HD = 640;  // Horizontal display pixels
    parameter HF = 16;   // Horizontal front porch
    parameter HB = 48;   // Horizontal back porch
    parameter HR = 96;   // Horizontal sync pulse
    
    parameter VM = 524;  // Total vertical lines - 1
    parameter VD = 480;  // Vertical display lines
    parameter VF = 10;   // Vertical front porch
    parameter VB = 33;   // Vertical back porch
    parameter VR = 2;    // Vertical sync pulse
    
    // Counters
    reg [9:0] Hcnt = 10'd0;
    reg [9:0] Vcnt = 10'd520;  // Initialize to 520 (0x208)
    wire video;
    
    // Pixel counting for 320x240 window
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin  // End of line
            Hcnt <= 10'd0;
            if (Vcnt == VM) begin  // End of frame
                Vcnt <= 10'd0;
            end else begin
                Vcnt <= Vcnt + 1'b1;
            end
        end else begin
            Hcnt <= Hcnt + 1'b1;
        end
    end
    
    // Active area generation for 320x240 window
    always @(posedge CLK25) begin
        if ((Hcnt < 320) && (Vcnt < 240)) begin
            activeArea <= 1'b1;
        end else begin
            activeArea <= 1'b0;
        end
    end
    
    // Horizontal sync generation
    always @(posedge CLK25) begin
        if (Hcnt >= (HD + HF) && Hcnt <= (HD + HF + HR - 1))  // 656 to 751
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;
    end
    
    // Vertical sync generation
    always @(posedge CLK25) begin
        if (Vcnt >= (VD + VF) && Vcnt <= (VD + VF + VR - 1))  // 490 to 491
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end
    
    // Output assignments
    assign Nsync = 1'b1;
    assign video = (Hcnt < HD) && (Vcnt < VD);  // Full 640x480 resolution
    assign Nblank = video;
    assign clkout = CLK25;
    
endmodule