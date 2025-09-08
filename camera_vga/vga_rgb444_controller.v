module vga_rgb444_controller(
    input wire clk,
    input wire reset,
    
    // Memory interface
    output reg [14:0] mem_addr,
    input wire [15:0] mem_data,
    
    // VGA outputs
    output reg [7:0] vga_r,
    output reg [7:0] vga_g,
    output reg [7:0] vga_b,
    output reg vga_hs,
    output reg vga_vs,
    output reg vga_blank_n
);

    // Image parameters
    parameter IMG_WIDTH = 200;
    parameter IMG_HEIGHT = 160;
    
    // VGA timing
    parameter H_ACTIVE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48, H_TOTAL = 800;
    parameter V_ACTIVE = 480, V_FRONT = 10, V_SYNC = 2, V_BACK = 33, V_TOTAL = 525;
    
    // Image positioning (centered and scaled 3x)
    parameter SCALE_FACTOR = 3;  // 200x3 = 600, 160x3 = 480 (fits perfectly!)
    parameter IMG_START_X = 20,  // (640-600)/2
              IMG_END_X = 619,   // 20+599
              IMG_START_Y = 0,   // (480-480)/2
              IMG_END_Y = 479;   // 0+479
    
    reg [9:0] h_count, v_count;
    wire display_active, in_image_area;
    reg display_active_d1, in_image_area_d1;
    
    // Counters
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end
    
    assign display_active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign in_image_area = display_active && 
                          (h_count >= IMG_START_X) && (h_count <= IMG_END_X) &&
                          (v_count >= IMG_START_Y) && (v_count <= IMG_END_Y);
    
    // Memory address calculation (with 3x scaling)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_addr <= 15'd0;
        end else if (in_image_area) begin
            wire [7:0] img_y = (v_count - IMG_START_Y) / SCALE_FACTOR;
            wire [8:0] img_x = (h_count - IMG_START_X) / SCALE_FACTOR;
            mem_addr <= img_y * IMG_WIDTH + img_x;
        end
    end
    
    // Pipeline for BRAM latency
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            display_active_d1 <= 1'b0;
            in_image_area_d1 <= 1'b0;
        end else begin
            display_active_d1 <= display_active;
            in_image_area_d1 <= in_image_area;
        end
    end
    
    // Sync generation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            vga_hs <= ~((h_count >= H_ACTIVE + H_FRONT) && 
                       (h_count < H_ACTIVE + H_FRONT + H_SYNC));
            vga_vs <= ~((v_count >= V_ACTIVE + V_FRONT) && 
                       (v_count < V_ACTIVE + V_FRONT + V_SYNC));
        end
    end
    
    // RGB output (RGB444 to RGB888 conversion)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
            vga_blank_n <= 1'b0;
        end else begin
            vga_blank_n <= display_active_d1;
            
            if (in_image_area_d1) begin
                // RGB444 to RGB888 conversion
                // RGB444: ---- RRRR GGGG BBBB
                wire [3:0] r4 = mem_data[11:8];
                wire [3:0] g4 = mem_data[7:4];
                wire [3:0] b4 = mem_data[3:0];
                
                // Expand 4-bit to 8-bit by replication
                vga_r <= {r4, r4};
                vga_g <= {g4, g4};
                vga_b <= {b4, b4};
            end else begin
                vga_r <= 8'd0;
                vga_g <= 8'd0;
                vga_b <= 8'd0;
            end
        end
    end

endmodule
