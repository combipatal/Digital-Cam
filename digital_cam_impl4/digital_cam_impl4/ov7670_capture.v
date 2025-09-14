// Captures the pixels data of each frame coming from the OV7670 camera and
// Stores them in block RAM
// The length of href controls how often pixels are captive - (2 downto 0) stores
// one pixel every 4 cycles.
// "line" is used to control how often data is captured. In this case every forth
// line

module ov7670_capture(
    input pclk,
    input vsync,
    input href,
    input [7:0] d,
    output [16:0] addr,
    output [11:0] dout,
    output reg we,
    output reg end_of_frame
);

    reg [15:0] d_latch = 16'b0;
    reg [16:0] address = 17'b0;
    reg [1:0] line = 2'b0;
    reg [6:0] href_last = 7'b0;
    reg href_hold = 1'b0;
    reg latched_vsync, latched_href;
    reg [7:0] latched_d;

    assign addr = address;
    assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};

    always @(posedge pclk) begin
        if (we == 1'b1) begin
            address <= address + 1;
        end

        // This is a bit tricky href starts a pixel transfer that takes 3 cycles
        //        Input   | state after clock tick
        //         href   | wr_hold    d_latch           dout          we  address  address_next
        // cycle -1  x    |    xx      xxxxxxxxxxxxxxxx  xxxxxxxxxxxx  x   xxxx     xxxx
        // cycle 0   1    |    x1      xxxxxxxxRRRRRGGG  xxxxxxxxxxxx  x   xxxx     addr
        // cycle 1   0    |    10      RRRRRGGGGGGBBBBB  xxxxxxxxxxxx  x   addr     addr
        // cycle 2   x    |    0x      GGGBBBBBxxxxxxxx  RRRRGGGGBBBB  1   addr     addr+1

        // detect the rising edge on href - the start of the scan line
        if (href_hold == 1'b0 && latched_href == 1'b1) begin
            case (line)
                2'b00: line <= 2'b01;
                2'b01: line <= 2'b10;
                2'b10: line <= 2'b11;
                default: line <= 2'b00;
            endcase
        end
        href_hold <= latched_href;

        // capturing the data from the camera, 12-bit RGB
        if (latched_href == 1'b1) begin
            d_latch <= {d_latch[7:0], latched_d};
        end
        we <= 1'b0;

        // Is a new screen about to start (i.e., we have to restart capturing)
        if (latched_vsync == 1'b1) begin
            address <= 17'b0;
            href_last <= 7'b0;
            line <= 2'b0;
            end_of_frame <= 1'b1;
        end else begin
            // If not, set the write enable whenever we need to capture a pixel
            if (href_last[2] == 1'b1) begin
                if (line[1] == 1'b1) begin
                    we <= 1'b1;
                end
                href_last <= 7'b0;
            end else begin
                href_last <= {href_last[5:0], latched_href};
            end
            end_of_frame <= 1'b0;
        end
    end

    // Capture signals on falling edge of pclk
    always @(negedge pclk) begin
        latched_d <= d;
        latched_href <= href;
        latched_vsync <= vsync;
    end

endmodule
