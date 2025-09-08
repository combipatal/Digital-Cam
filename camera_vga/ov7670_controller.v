module ov7670_rgb444_controller(
    input wire clk,
    input wire reset,
    
    // OV7670 interface
    input wire ov7670_pclk,
    input wire ov7670_href,
    input wire ov7670_vsync,
    input wire [7:0] ov7670_data,
    output wire ov7670_sioc,
    inout wire ov7670_siod,
    output wire ov7670_reset,
    output wire ov7670_pwdn,
    
    // Memory interface
    output reg [14:0] mem_addr,    // 15-bit for up to 32768 pixels
    output reg [15:0] mem_data,    // 16-bit with RGB444 in lower 12 bits
    output reg mem_wren,
    output reg data_valid,
    output wire config_done
);

    // Image size parameters
    parameter IMG_WIDTH = 200;
    parameter IMG_HEIGHT = 160;
    parameter MAX_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 32,000
    
    assign ov7670_reset = ~reset;
    assign ov7670_pwdn = 1'b0;
    
    // Pixel capture state machine
    reg [2:0] capture_state;
    reg [7:0] pixel_high, pixel_low;
    reg vsync_prev, href_prev;
    reg frame_start;
    reg [8:0] pixel_x;  // up to 200
    reg [7:0] pixel_y;  // up to 160
    
    parameter IDLE = 3'd0,
              WAIT_FRAME = 3'd1,
              CAPTURE_HIGH = 3'd2,
              CAPTURE_LOW = 3'd3,
              PROCESS_PIXEL = 3'd4;
    
    // I2C configuration for RGB444
    ov7670_i2c_rgb444_config i2c_config(
        .clk(clk),
        .reset(reset),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .config_done(config_done)
    );
    
    // Edge detection
    always @(posedge ov7670_pclk or posedge reset) begin
        if (reset) begin
            vsync_prev <= 1'b0;
            href_prev <= 1'b0;
        end else begin
            vsync_prev <= ov7670_vsync;
            href_prev <= ov7670_href;
        end
    end
    
    always @(posedge ov7670_pclk or posedge reset) begin
        if (reset) begin
            frame_start <= 1'b0;
        end else begin
            frame_start <= vsync_prev & ~ov7670_vsync;
        end
    end
    
    // Pixel capture and RGB565 to RGB444 conversion
    always @(posedge ov7670_pclk or posedge reset) begin
        if (reset) begin
            capture_state <= IDLE;
            mem_addr <= 15'd0;
            mem_data <= 16'd0;
            mem_wren <= 1'b0;
            pixel_x <= 9'd0;
            pixel_y <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            case (capture_state)
                IDLE: begin
                    mem_wren <= 1'b0;
                    data_valid <= 1'b0;
                    if (frame_start) begin
                        capture_state <= WAIT_FRAME;
                        mem_addr <= 15'd0;
                        pixel_x <= 9'd0;
                        pixel_y <= 8'd0;
                    end
                end
                
                WAIT_FRAME: begin
                    if (ov7670_href && !href_prev) begin
                        capture_state <= CAPTURE_HIGH;
                        pixel_x <= 9'd0;
                    end else if (!ov7670_href && href_prev) begin
                        if (pixel_y < IMG_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end else begin
                            capture_state <= IDLE;
                        end
                    end
                end
                
                CAPTURE_HIGH: begin
                    if (ov7670_href) begin
                        pixel_high <= ov7670_data;  // RGB565 high byte
                        capture_state <= CAPTURE_LOW;
                    end else begin
                        capture_state <= WAIT_FRAME;
                    end
                end
                
                CAPTURE_LOW: begin
                    if (ov7670_href) begin
                        pixel_low <= ov7670_data;   // RGB565 low byte
                        capture_state <= PROCESS_PIXEL;
                    end else begin
                        capture_state <= WAIT_FRAME;
                    end
                end
                
                PROCESS_PIXEL: begin
                    if (pixel_x < IMG_WIDTH && pixel_y < IMG_HEIGHT) begin
                        // RGB565 to RGB444 conversion
                        // RGB565: RRRRRGGG GGGBBBBB
                        // RGB444: ---- RRRR GGGG BBBB
                        wire [4:0] r5 = pixel_high[7:3];
                        wire [5:0] g6 = {pixel_high[2:0], pixel_low[7:5]};
                        wire [4:0] b5 = pixel_low[4:0];
                        
                        // Convert to 4-bit each
                        wire [3:0] r4 = r5[4:1];    // Take upper 4 bits
                        wire [3:0] g4 = g6[5:2];    // Take upper 4 bits  
                        wire [3:0] b4 = b5[4:1];    // Take upper 4 bits
                        
                        mem_data <= {4'b0000, r4, g4, b4}; // RGB444 in lower 12 bits
                        mem_wren <= 1'b1;
                        data_valid <= 1'b1;
                        mem_addr <= pixel_y * IMG_WIDTH + pixel_x;
                        pixel_x <= pixel_x + 1;
                    end else begin
                        mem_wren <= 1'b0;
                    end
                    
                    capture_state <= CAPTURE_HIGH;
                end
                
                default: capture_state <= IDLE;
            endcase
        end
    end

endmodule
