// OV7670 capture with 2×2 average decimation (RGB565 -> RGB565).
// - Assembles incoming RGB565 bytes from OV7670
// - Performs 2x2 box filter (average) in sensor domain (640x480 -> 320x240)
// - Writes decimated pixels directly to a linear BRAM (addr auto-increments)
// I/O kept compatible with existing design.
module ov7670_capture #(
    parameter integer SRC_H           = 640,
    parameter integer SRC_V           = 480,
    parameter integer DST_H           = 320,
    parameter integer DST_V           = 240,
    parameter         HI_BYTE_FIRST   = 1,  // 1: [15:8] then [7:0]
    parameter         BGR_ORDER       = 0   // 0: RGB565, 1: BGR565 output swap
)(
    input  wire        pclk,    // pixel clock from camera
    input  wire        vsync,   // active-high frame sync (reset on rising)
    input  wire        href,    // active-high line valid
    input  wire [7:0]  d,       // pixel bus
    output wire [16:0] addr,    // linear write address (0..(DST_H*DST_V-1))
    output wire [15:0] dout,    // RGB565 write data
    output reg         we       // write strobe (one pclk for each output pixel)
);

    // -------- Sync edge detection --------
    reg vsync_d, href_d;
    always @(posedge pclk) begin
        vsync_d <= vsync;
        href_d  <= href;
    end
    wire vsync_rise = (vsync && !vsync_d);
    wire href_rise  = (href  && !href_d);
    wire href_fall  = (!href &&  href_d);

    // -------- Byte assembly (RGB565) --------
    reg        byte_phase;        // 0: first byte, 1: second byte
    reg [7:0]  first_byte;
    reg [15:0] pix16;
    reg        pix_valid;

    // -------- Pixel coordinate tracking (source) --------
    reg [9:0]  src_x;             // 0..639 within current source line
    reg        line_parity;       // 0: even line of 2x2, 1: odd line of 2x2
    reg [8:0]  decim_x;           // 0..319 index for decimated x

    // -------- Horizontal 2-pixel sum per color (current & previous line) --------
    // Pack = {R_sum2[5:0], G_sum2[6:0], B_sum2[5:0]} = 19 bits
    reg [18:0] hpair_sum_prev [0:DST_H-1];

    // Working regs
    reg [4:0] r5, r5_p0, b5, b5_p0, r_avg5, b_avg5;
    reg [5:0] g6, g6_p0, g_avg6;
    reg [5:0] r_sum2, b_sum2, r_prev2, b_prev2;   // 0..62
    reg [6:0] g_sum2, g_prev2;                    // 0..126
    reg [6:0] r_sum4, b_sum4;                     // 0..124
    reg [7:0] g_sum4;                             // 0..252
    reg [18:0] prev_pack;
    reg [15:0] out_pix;

    // -------- Address generator (linear, auto-increment) --------
    reg [16:0] wr_addr;
    assign addr = wr_addr;
    assign dout = out_pix;

    // -------- Reset/Start of frame --------
    always @(posedge pclk) begin
        if (vsync_rise) begin
            // Reset frame state
            byte_phase  <= 1'b0;
            pix_valid   <= 1'b0;
            src_x       <= 10'd0;
            line_parity <= 1'b0;
            decim_x     <= 9'd0;
            we          <= 1'b0;
            wr_addr     <= 17'd0;
        end else begin
            we <= 1'b0; // default

            // HREF gating
            if (href_rise) begin
                byte_phase  <= 1'b0;
                pix_valid   <= 1'b0;
                src_x       <= 10'd0;
                decim_x     <= 9'd0;
            end

            // Assemble bytes into RGB565 pixel
            if (href) begin
                if (!byte_phase) begin
                    first_byte <= d;
                    byte_phase <= 1'b1;
                    pix_valid  <= 1'b0;
                end else begin
                    // Second byte -> pixel complete this cycle
                    byte_phase <= 1'b0;
                    pix_valid  <= 1'b1;
                    if (HI_BYTE_FIRST)
                        pix16 <= {first_byte, d};
                    else
                        pix16 <= {d, first_byte};
                end
            end else begin
                byte_phase <= 1'b0;
                pix_valid  <= 1'b0;
            end

            // On each completed source pixel, advance src_x and perform 2x2 accumulate
            if (pix_valid) begin
                // Unpack RGB565 to components
                // pix16[15:11]=R5, [10:5]=G6, [4:0]=B5 (for RGB order)
                r5 = pix16[15:11];
                g6 = pix16[10:5];
                b5 = pix16[4:0];

                // Horizontal pair logic: combine two pixels per 2x block
                if (src_x[0] == 1'b0) begin
                    // even column: remember current as P0
                    r5_p0 <= r5;
                    g6_p0 <= g6;
                    b5_p0 <= b5;
                end else begin
                    // odd column: accumulate current with P0 => 2-pixel sums
                    r_sum2 = r5_p0 + r5;  // 6-bit
                    g_sum2 = g6_p0 + g6;  // 7-bit
                    b_sum2 = b5_p0 + b5;  // 6-bit

                    // Store or output depending on line parity
                    if (line_parity == 1'b0) begin
                        // Even source line: store horizontal sums, no output
                        hpair_sum_prev[decim_x] <= {r_sum2, g_sum2, b_sum2};
                    end else begin
                        // Odd source line: fetch previous sums and produce averaged pixel
                        prev_pack = hpair_sum_prev[decim_x];
                        r_prev2   = prev_pack[18:13];
                        g_prev2   = prev_pack[12:6];
                        b_prev2   = prev_pack[5:0];

                        r_sum4 = r_prev2 + r_sum2; // 7b
                        g_sum4 = g_prev2 + g_sum2; // 8b
                        b_sum4 = b_prev2 + b_sum2; // 7b

                        // Divide by 4 (>>2) to get average, keep RGB565 widths
                        r_avg5 = r_sum4[6:2];
                        g_avg6 = g_sum4[7:2];
                        b_avg5 = b_sum4[6:2];

                        // Repack (optionally swap RB)
                        if (!BGR_ORDER)
                            out_pix <= {r_avg5, g_avg6, b_avg5};
                        else
                            out_pix <= {b_avg5, g_avg6, r_avg5};

                        // Emit one averaged pixel
                        we      <= 1'b1;
                        wr_addr <= wr_addr + 17'd1;
                    end

                    // Advance 2-pixel column index at each odd column
                    if (decim_x != DST_H-1)
                        decim_x <= decim_x + 9'd1;
                end

                // Advance source x each completed pixel
                if (src_x != SRC_H-1)
                    src_x <= src_x + 10'd1;
            end

            // At end of line, toggle parity
            if (href_fall) begin
                line_parity <= ~line_parity;
            end
        end
    end
endmodule
