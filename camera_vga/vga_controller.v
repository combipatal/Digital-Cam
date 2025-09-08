module vga_controller(
    input wire clk,         // 25MHz VGA clock
    input wire reset,
    
    // Memory interface
    output reg [16:0] mem_addr,
    input wire [15:0] mem_data,
    
    // VGA outputs
    output reg [7:0] vga_r,
    output reg [7:0] vga_g,
    output reg [7:0] vga_b,
    output reg vga_hs,
    output reg vga_vs,
    output reg vga_blank_n
);

    // VGA 640x480 timing parameters
    parameter H_ACTIVE = 640,
              H_FRONT = 16,
              H_SYNC = 96,
              H_BACK = 48,
              H_TOTAL = 800;
              
    parameter V_ACTIVE = 480,
              V_FRONT = 10,
              V_SYNC = 2,
              V_BACK = 33,
              V_TOTAL = 525;
    
    // Display area for 320x240 image (centered in 640x480)
    parameter IMG_START_X = 160,  // (640-320)/2
              IMG_END_X = 479,    // 160+319
              IMG_START_Y = 120,  // (480-240)/2
              IMG_END_Y = 359;    // 120+239
    
    reg [9:0] h_count, v_count;
    reg [8:0] img_x, img_y;
    wire display_active;
    wire in_image_area;
    
    // Horizontal and vertical counters
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
    
    // Active display area
    assign display_active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    
    // Image area detection
    assign in_image_area = display_active && 
                          (h_count >= IMG_START_X) && (h_count <= IMG_END_X) &&
                          (v_count >= IMG_START_Y) && (v_count <= IMG_END_Y);
    
    // Image coordinates (with 2x scaling)
    always @(*) begin
        img_x = (h_count - IMG_START_X) >> 1;  // Divide by 2 for scaling
        img_y = (v_count - IMG_START_Y) >> 1;
    end
    
    // Memory address calculation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_addr <= 17'd0;
        end else if (in_image_area) begin
            mem_addr <= img_y * 320 + img_x;  // Row * width + column
        end
    end
    
    // RGB output generation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
            vga_blank_n <= 1'b0;
        end else begin
            vga_blank_n <= display_active;
            
            if (in_image_area) begin
                // Convert RGB565 to RGB888
                vga_r <= {mem_data[15:11], mem_data[15:13]};  // 5-bit to 8-bit
                vga_g <= {mem_data[10:5], mem_data[10:9]};    // 6-bit to 8-bit
                vga_b <= {mem_data[4:0], mem_data[4:2]};      // 5-bit to 8-bit
            end else begin
                // Black background outside image area
                vga_r <= 8'd0;
                vga_g <= 8'd0;
                vga_b <= 8'd0;
            end
        end
    end

endmodule
