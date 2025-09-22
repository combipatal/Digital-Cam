// 3x3 Gaussian blur for 8-bit grayscale
module gaussian_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,
    input  wire        vsync,
    input  wire        active_area,
    output reg  [7:0]  pixel_out,
    output reg         filter_ready
);

    // init and vsync edge
    reg vsync_prev = 1'b0;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev <= vsync;
        active_prev <= active_area;
    end

    reg        reset_done = 1'b0;
    reg [2:0]  init_counter = 3'd0; // 0..5 -> 6 clocks to prime 3x3 window

    // 3x3 window caches (line buffers collapsed as 3 shift registers of width 8)
    reg [7:0] cache1 [0:2];
    reg [7:0] cache2 [0:2];
    reg [7:0] cache3 [0:2];

    wire valid_addr = 1'b1; // top drives pixel_addr progression, here we only guard with active_area

    // window taps
    wire [7:0] g00 = cache1[0];
    wire [7:0] g01 = cache1[1];
    wire [7:0] g02 = cache1[2];
    wire [7:0] g10 = cache2[0];
    wire [7:0] g11 = cache2[1];
    wire [7:0] g12 = cache2[2];
    wire [7:0] g20 = cache3[0];
    wire [7:0] g21 = cache3[1];
    wire [7:0] g22 = cache3[2];

    // stage-1 accumulators (max 16*255 = 4080 -> 12 bits)
    reg [11:0] sum_blur = 12'd0;


    // line/window maintenance
    always @(posedge clk) begin
        if ((vsync && !vsync_prev) || (active_area && !active_prev)) begin
            reset_done   <= 1'b0;
            init_counter <= 3'd0;
            cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
            cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
            cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
        end else if (enable && valid_addr && active_area) begin
            if (!reset_done) begin
                if (init_counter < 3'd5) begin
                    init_counter <= init_counter + 1'b1;
                    cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
                    cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
                    cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
                end else begin
                    reset_done <= 1'b1;
                    cache1[0] <= cache1[1];
                    cache1[1] <= cache1[2];
                    cache1[2] <= cache2[1];

                    cache2[0] <= cache2[1];
                    cache2[1] <= cache2[2];
                    cache2[2] <= cache3[1];

                    cache3[0] <= cache3[1];
                    cache3[1] <= cache3[2];
                    cache3[2] <= pixel_in;
                end
            end else begin
                reset_done <= 1'b0;
            end
        end else begin
             reset_done <= 1'b0; // Reset if not active
        end
    end

    // stage 1: weighted sum (kernel /16)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            sum_blur <= (g00 + g02 + g20 + g22)
                      + ((g01 + g10 + g12 + g21) << 1)
                      + (g11 << 2);
        end else begin
            sum_blur <= 12'd0;
        end
    end

    // stage 2: normalize and output
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            pixel_out   <= sum_blur[11:4]; // divide by 16
            filter_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            filter_ready <= 1'b0;
        end
    end

endmodule


