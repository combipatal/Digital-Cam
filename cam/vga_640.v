// VGA controller with 2x up-scaling (nearest neighbour) from 320x240 source
// to 640x480 output.  Generates 640x480@60Hz timing while mapping display
// coordinates to the underlying 320x240 frame buffer.  For each display pixel,
// the corresponding source coordinate is calculated as (x>>1, y>>1) so the
// same pixel/line is repeated twice horizontally and vertically.  The
// pixel_address therefore follows the pattern 0,0,1,1,... for each line and
// repeats the same line address for two consecutive VGA lines.  The activeArea
// output asserts during the entire 640x480 visible region so downstream image
// processing modules must be configured for IMG_WIDTH=640 and IMG_HEIGHT=480.
module vga_640 (
    input  wire        CLK25,          // 25 MHz pixel clock
    input  wire [15:0] pixel_data,     // unused but kept for interface match
    output wire        clkout,         // pixel clock to DAC
    output reg         Hsync,
    output reg         Vsync,
    output wire        Nblank,
    output reg         activeArea,     // asserted during 640x480 visible area
    output wire        Nsync,
    output reg [16:0]  pixel_address   // frame-buffer read address (RGB565)
);

    // 640x480@60Hz timing parameters (same as original VGA module)
    localparam integer HM = 799;  // horizontal total - 1
    localparam integer HD = 640;  // horizontal display
    localparam integer HF = 16;   // horizontal front porch
    localparam integer HB = 48;   // horizontal back porch
    localparam integer HR = 96;   // horizontal sync pulse width

    localparam integer VM = 524;  // vertical total - 1
    localparam integer VD = 480;  // vertical display
    localparam integer VF = 10;   // vertical front porch
    localparam integer VB = 33;   // vertical back porch
    localparam integer VR = 2;    // vertical sync pulse width

    // Horizontal/vertical counters
    reg [9:0] Hcnt = 10'd0;
    reg [9:0] Vcnt = 10'd0;

    // Increment timing counters
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin
            Hcnt <= 10'd0;
            if (Vcnt == VM)
                Vcnt <= 10'd0;
            else
                Vcnt <= Vcnt + 1'b1;
        end else begin
            Hcnt <= Hcnt + 1'b1;
        end
    end

    // VGA sync generation (active low pulses)
    always @(posedge CLK25) begin
        if (Hcnt >= (HD + HF) && Hcnt <= (HD + HF + HR - 1))
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;
    end

    always @(posedge CLK25) begin
        if (Vcnt >= (VD + VF) && Vcnt <= (VD + VF + VR - 1))
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end

    assign Nsync = 1'b1;                         // not used by ADV7123
    wire video_active = (Hcnt < HD) && (Vcnt < VD);
    assign Nblank = video_active;                 // assert during visible area
    assign clkout = CLK25;
    
    // activeArea는 639 픽셀만 활성화 (마지막 픽셀 제외하여 라인 넘김 방지)
    wire active_limited = (Hcnt < (HD - 1)) && (Vcnt < VD);

    // Issue frame-buffer addresses two cycles ahead. Timing flow:
    // Clk N: Hcnt=N → addr_next=addr(N+2) [comb]
    // Clk N+1: pixel_address=addr(N+2) [reg], rdaddress=addr(N+2) → RAM input
    // Clk N+2: Hcnt=N+2, RAM output=data(N+2) [+1 total], activeArea_d1 valid
    localparam [10:0] PREFETCH     = 11'd0;
    localparam [10:0] LINE_PERIOD  = 11'd800; // HM + 1

    wire [10:0] h_prefetch_full = {1'b0, Hcnt} + PREFETCH;
    wire        wrap_next_line  = (h_prefetch_full >= LINE_PERIOD);
    wire [9:0]  h_fetch = wrap_next_line ?
                          (h_prefetch_full - LINE_PERIOD) :
                          h_prefetch_full[9:0];
    wire [9:0]  v_fetch = wrap_next_line ?
                          ((Vcnt == VM) ? 10'd0 : (Vcnt + 1'b1)) :
                          Vcnt;

    wire fetch_active = (h_fetch < HD) && (v_fetch < VD);
    wire fetch_limited = (h_fetch < (HD - 1)) && (v_fetch < VD);  // 639 픽셀만

    // Maintain activeArea flag aligned with fetch timing (마지막 픽셀 제외)
    always @(posedge CLK25) begin
        activeArea <= fetch_limited;
    end

    wire [8:0] src_x = h_fetch[9:1];      // divide by 2 (0..319)
    wire [8:0] src_y = v_fetch[9:1];      // divide by 2 (0..239)

    // src_y * 320 = src_y * (256 + 64) = (src_y << 8) + (src_y << 6)
    wire [16:0] line_base = {src_y, 8'b0} + {src_y, 6'b0};
    wire [16:0] addr_next = line_base + {8'b0, src_x};

    // Register the computed address
    always @(posedge CLK25) begin
        if (fetch_active)
            pixel_address <= addr_next;
        else
            pixel_address <= 17'd0;
    end

endmodule
