`timescale 1ns/1ps
module tb_digital_cam;

    localparam integer FRAME_WIDTH   = 320;
    localparam integer FRAME_HEIGHT  = 240;
    localparam integer FRAME_PIXELS  = FRAME_WIDTH * FRAME_HEIGHT;
    localparam integer IMG_WIDTH     = 640;
    localparam integer IMG_HEIGHT    = 480;
    localparam integer IDX_MAX       = IMG_WIDTH * IMG_HEIGHT;

    localparam [2:0] MODE_BG_SUB = 3'd5;

    localparam [1:0] PHASE_BG_LOAD        = 2'd0;
    localparam [1:0] PHASE_WAIT_FOR_VSYNC = 2'd1;
    localparam [1:0] PHASE_FG_LOAD        = 2'd2;
    localparam [1:0] PHASE_DONE           = 2'd3;

    reg clk_50MHz;
    reg clk_25MHz;
    reg wren;
    reg [16:0] wraddress;
    reg [15:0] wrdata;
    reg [2:0] active_filter_mode;

    wire vga_enable;
    wire pixel_valid;
    wire vsync;

    wire [7:0] sobel_value;
    wire [7:0] gaussian_value;
    wire [7:0] canny_value;
    wire color_track_mask;
    wire color_track_ready;
    wire sobel_ready;
    wire gaussian_ready;
    wire canny_ready;
    wire adaptive_fg_mask;
    wire [15:0] pixel_rgb565;

    reg [15:0] frame_bg_mem [0:FRAME_PIXELS-1];
    reg [15:0] frame_fg_mem [0:FRAME_PIXELS-1];

    reg [1:0] write_phase;
    reg [16:0] idx;

    reg capture_arm;
    reg capture_active;
    reg vsync_prev;

    wire vsync_rise = (~vsync_prev) && vsync;

    integer px_fd;
    reg [31:0] px_cnt;
    reg [15:0] px_value;

    test_digital_cam_top test_digital_cam_top_inst (
        .clk_50MHz(clk_50MHz),
        .clk_25MHz(clk_25MHz),
        .wren(wren),
        .wraddress(wraddress),
        .wrdata(wrdata),
        .active_filter_mode(active_filter_mode),
        .vga_enable(vga_enable),
        .pixel_valid(pixel_valid),
        .sobel_value(sobel_value),
        .sobel_ready(sobel_ready),
        .gaussian_value(gaussian_value),
        .gaussian_ready(gaussian_ready),
        .color_track_mask(color_track_mask),
        .color_track_ready(color_track_ready),
        .canny_value(canny_value),
        .canny_ready(canny_ready),
        .adaptive_fg_mask(adaptive_fg_mask),
        .pixel_rgb565(pixel_rgb565),
        .vsync(vsync)
    );

    initial begin
        $readmemh("C:/git/Verilog-HDL/cam/out_background.hex", frame_bg_mem);
        $readmemh("C:/git/Verilog-HDL/cam/out_color_tracker.hex", frame_fg_mem);

        clk_50MHz = 1'b0;
        clk_25MHz = 1'b0;
        wren = 1'b0;
        wraddress = 17'd0;
        wrdata = 16'd0;
        active_filter_mode = MODE_BG_SUB;

        write_phase = PHASE_BG_LOAD;
        idx = 17'd0;

        capture_arm = 1'b0;
        capture_active = 1'b0;
        vsync_prev = 1'b1;

        px_fd = $fopen("C:/git/Verilog-HDL/cam/px_background.hex", "w");
        if (px_fd == 0) begin
            $display("Failed to open px_background.hex file");
        end
        px_cnt = 0;
    end

    always #10 clk_50MHz = ~clk_50MHz;
    always #20 clk_25MHz = ~clk_25MHz;

    always @(posedge clk_25MHz) begin
        vsync_prev <= vsync;

        case (write_phase)
            PHASE_BG_LOAD: begin
                if (idx < FRAME_PIXELS) begin
                    wren <= 1'b1;
                    wraddress <= idx;
                    wrdata <= frame_bg_mem[idx];
                    idx <= idx + 1'b1;
                end else begin
                    wren <= 1'b0;
                    write_phase <= PHASE_WAIT_FOR_VSYNC;
                end
            end
            PHASE_WAIT_FOR_VSYNC: begin
                wren <= 1'b0;
                if (vsync_rise) begin
                    idx <= 17'd0;
                    write_phase <= PHASE_FG_LOAD;
                end
            end
            PHASE_FG_LOAD: begin
                if (idx < FRAME_PIXELS) begin
                    wren <= 1'b1;
                    wraddress <= idx;
                    wrdata <= frame_fg_mem[idx];
                    idx <= idx + 1'b1;
                end else begin
                    wren <= 1'b0;
                    write_phase <= PHASE_DONE;
                    capture_arm <= 1'b1;
                end
            end
            default: begin
                wren <= 1'b0;
            end
        endcase
    end

    always @(posedge clk_25MHz) begin
        if (vsync_rise) begin
            if (capture_arm) begin
                capture_active <= 1'b1;
                capture_arm <= 1'b0;
                px_cnt <= 0;
            end else if (capture_active) begin
                capture_active <= 1'b0;
            end
        end

        if (capture_active && pixel_valid) begin
            px_value = adaptive_fg_mask ? pixel_rgb565 : 16'h0000;
            $fwrite(px_fd, "%04h\n", px_value);
            px_cnt <= px_cnt + 1'b1;
            if (px_cnt == IDX_MAX - 1) begin
                $display("Pixel dump completed (Background Subtraction)");
                $fclose(px_fd);
                capture_active <= 1'b0;
                $finish;
            end
        end
    end

endmodule
