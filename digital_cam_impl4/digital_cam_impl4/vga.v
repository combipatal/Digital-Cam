// VGA timing generator
// Let's brush up our French here; :-)

module VGA(
    input CLK25,         // 25 MHz input clock
    output reg clkout,   // Clock output to ADV7123 and TFT screen
    output reg Hsync,    // Horizontal sync signal for VGA screen
    output reg Vsync,    // Vertical sync signal for VGA screen
    output reg Nblank,   // Command signal for ADV7123 converter
    output reg activeArea, // Active display area
    output Nsync         // Sync signal and command for TFT screen
);

    reg [9:0] Hcnt = 10'b0; // for counting columns
    reg [9:0] Vcnt = 10'b1000001000; // for counting lines
    reg video;

    // VGA timing constants
    localparam HM = 799;  // maximum considered size 800 (horizontal)
    localparam HD = 640;  // screen size (horizontal)
    localparam HF = 16;   // front porch
    localparam HB = 48;   // back porch
    localparam HR = 96;   // sync time
    localparam VM = 524;  // maximum considered size 525 (vertical)
    localparam VD = 480;  // screen size (vertical)
    localparam VF = 10;   // front porch
    localparam VB = 33;   // back porch
    localparam VR = 2;    // retrace

    assign Nsync = 1'b1;

    // Counter initialization from 0 to 799 (800 pixels per line):
    // at each clock edge increment the counter from 0 to 799.
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin // 799
            Hcnt <= 10'b0;
            if (Vcnt == VM) begin // 524
                Vcnt <= 10'b0;
                activeArea <= 1'b1;
            end else begin
                if (Vcnt < 240-1) begin
                    activeArea <= 1'b1;
                end
                Vcnt <= Vcnt + 1;
            end
        end else begin
            if (Hcnt == 320-1) begin
                activeArea <= 1'b0;
            end
            Hcnt <= Hcnt + 1;
        end
    end

    // Generate horizontal sync signal Hsync:
    always @(posedge CLK25) begin
        if (Hcnt >= (HD+HF) && Hcnt <= (HD+HF+HR-1)) begin // Hcnt >= 656 and Hcnt <= 751
            Hsync <= 1'b0;
        end else begin
            Hsync <= 1'b1;
        end
    end

    // Generate vertical sync signal Vsync:
    always @(posedge CLK25) begin
        if (Vcnt >= (VD+VF) && Vcnt <= (VD+VF+VR-1)) begin  // Vcnt >= 490 and vcnt<= 491
            Vsync <= 1'b0;
        end else begin
            Vsync <= 1'b1;
        end
    end

    // Nblank and Nsync for ADV7123 converter control:
    always @* begin
        video = ((Hcnt < HD) && (Vcnt < VD)) ? 1'b1 : 1'b0; // for using full resolution 640 x 480
        Nblank = video;
        clkout = CLK25;
    end

endmodule
