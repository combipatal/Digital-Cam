`timescale 1ns / 1ps

module bram_interface(
    input wire clk,
    input wire rst_n,
    
    // Camera FIFO interface
    input wire [15:0] camera_fifo_count, // 16-bit for 64K FIFO
    input wire [15:0] camera_fifo_data,
    output reg rd_camera_fifo,
    
    // VGA interface
    input wire vga_rd_en,
    input wire [11:0] vga_pixel_x,
    input wire [11:0] vga_pixel_y,
    output reg [15:0] vga_pixel_data,
    output reg vga_data_valid,
    
    // Control signals
    input wire sobel_mode,    // 0: original, 1: sobel
    output wire [3:0] led_status
);

    localparam WIDTH = 320;
    localparam HEIGHT = 240;
    localparam TOTAL_PIXELS = WIDTH * HEIGHT; // 76800
    
    // Frame buffer instantiation
    wire fb_wr_en;
    wire [15:0] fb_wr_data;
    wire [16:0] fb_wr_addr;
    wire fb_rd_en;
    wire [16:0] fb_rd_addr;
    wire [15:0] fb_rd_data;
    
    bram_frame_buffer frame_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(fb_wr_en),
        .wr_data(fb_wr_data),
        .wr_addr(fb_wr_addr),
        .rd_en(fb_rd_en),
        .rd_addr(fb_rd_addr),
        .rd_data(fb_rd_data),
        .sobel_mode(sobel_mode)
    );
    
    // Sobel filter instantiation
    wire sobel_start;
    wire sobel_done;
    wire sobel_pixel_valid;
    wire [15:0] sobel_pixel_data;
    wire [16:0] sobel_fb_addr;
    wire [15:0] sobel_fb_data;
    
    bram_sobel_filter sobel_filter (
        .clk(clk),
        .rst_n(rst_n),
        .fb_addr(sobel_fb_addr),
        .fb_data(sobel_fb_data),
        .pixel_valid(sobel_pixel_valid),
        .pixel_data(sobel_pixel_data),
        .start_process(sobel_start),
        .process_done(sobel_done)
    );
    
    // State machine for frame processing
    reg [2:0] state;
    reg [16:0] pixel_addr;
    reg [16:0] frame_start_addr;
    reg frame_ready;
    reg [3:0] read_delay; // VGA 읽기 지연 카운터 추가
    
    localparam IDLE = 0;
    localparam WRITE_FRAME = 1;
    localparam FRAME_COMPLETE = 2;
    localparam SOBEL_PROCESS = 3;
    
    // Frame buffer connections
    assign fb_wr_en = (state == WRITE_FRAME && rd_camera_fifo);
    assign fb_wr_data = camera_fifo_data;
    assign fb_wr_addr = pixel_addr;
    
    // VGA 좌표를 카메라 좌표로 매핑 (중앙 배치)
    wire [11:0] camera_x, camera_y;
    wire in_camera_region;
    assign in_camera_region = (vga_pixel_x >= 160 && vga_pixel_x < 480 && vga_pixel_y >= 120 && vga_pixel_y < 360);
    assign camera_x = in_camera_region ? (vga_pixel_x - 160) : 0;
    assign camera_y = in_camera_region ? (vga_pixel_y - 120) : 0;
    assign fb_rd_addr = camera_y * WIDTH + camera_x;
    assign fb_rd_en = vga_rd_en && in_camera_region && (state == FRAME_COMPLETE || state == SOBEL_PROCESS);
    
    // Sobel filter connections
    assign sobel_fb_data = fb_rd_data;
    assign sobel_start = (state == FRAME_COMPLETE && sobel_mode);
    
    // VGA output with improved timing
    always @(posedge clk) begin
        if (!rst_n) begin
            vga_pixel_data <= 0;
            vga_data_valid <= 0;
            read_delay <= 0;
        end else begin
            read_delay <= read_delay + 1;
            
            // 소벨 모드가 활성화되고 소벨 필터에서 유효한 픽셀이 나올 때
            if (sobel_mode && sobel_pixel_valid && state == SOBEL_PROCESS) begin
                vga_pixel_data <= sobel_pixel_data;
                vga_data_valid <= 1;
            end 
            // 일반 모드이거나 소벨이 완료된 후 프레임 버퍼에서 읽기
            else if (fb_rd_en && in_camera_region && frame_ready) begin
                vga_pixel_data <= fb_rd_data;
                vga_data_valid <= 1;
            end 
            // 카메라 영역 밖이거나 데이터가 없는 경우
            else begin
                vga_pixel_data <= 16'h0000; // 검은색
                vga_data_valid <= vga_rd_en; // VGA가 읽기를 요청할 때만 유효
            end
        end
    end
    
    // Main state machine
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_addr <= 0;
            frame_start_addr <= 0;
            rd_camera_fifo <= 0;
            frame_ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    rd_camera_fifo <= 0;
                    // 충분한 데이터가 있을 때 프레임 쓰기 시작 (한 프레임 정도)
                    if (camera_fifo_count >= TOTAL_PIXELS/4) begin // 1/4 프레임 정도 버퍼링
                        state <= WRITE_FRAME;
                        pixel_addr <= 0;
                        frame_start_addr <= 0;
                        rd_camera_fifo <= 1;
                        frame_ready <= 0;
                    end
                end
                
                WRITE_FRAME: begin
                    if (camera_fifo_count > 0 && pixel_addr < TOTAL_PIXELS) begin
                        pixel_addr <= pixel_addr + 1;
                        rd_camera_fifo <= 1;
                        if (pixel_addr == TOTAL_PIXELS - 1) begin
                            state <= FRAME_COMPLETE;
                            frame_ready <= 1;
                            rd_camera_fifo <= 0;
                        end
                    end else if (camera_fifo_count == 0) begin
                        // 데이터가 없으면 대기
                        rd_camera_fifo <= 0;
                        if (pixel_addr > TOTAL_PIXELS/2) begin
                            // 절반 이상 쓰여졌으면 완료로 간주
                            state <= FRAME_COMPLETE;
                            frame_ready <= 1;
                        end else begin
                            // 아니면 처음부터 다시
                            state <= IDLE;
                            pixel_addr <= 0;
                        end
                    end
                end
                
                FRAME_COMPLETE: begin
                    rd_camera_fifo <= 0;
                    if (sobel_mode) begin
                        state <= SOBEL_PROCESS;
                    end else begin
                        // 일반 모드에서는 새 프레임을 기다림
                        if (camera_fifo_count >= TOTAL_PIXELS/4) begin
                            state <= WRITE_FRAME;
                            pixel_addr <= 0;
                            rd_camera_fifo <= 1;
                        end
                    end
                end
                
                SOBEL_PROCESS: begin
                    if (sobel_done) begin
                        state <= IDLE;
                        frame_ready <= 1; // 소벨 처리 완료 후에도 프레임은 유효
                        pixel_addr <= 0;
                    end
                end
            endcase
        end
    end
    
    // LED status output - 카메라 FIFO 상태와 프레임 상태 표시
    assign led_status = {frame_ready, sobel_mode, state[1:0]}; 

endmodule