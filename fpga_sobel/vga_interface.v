`timescale 1ns / 1ps

module vga_interface(
    input wire clk, rst_n, // Main clock (50MHz)
    input wire sobel,
    // BRAM IO (from bram_interface)
    input wire empty_fifo,
    input wire[15:0] din,
    // VGA Control
    input wire clk_vga, // VGA clock from top_module (25MHz)
    output reg rd_en, // Generated in vga_clk domain
    input wire[7:0] threshold,
    // Pixel coordinates output (to bram_interface)
    output wire[11:0] pixel_x,
    output wire[11:0] pixel_y,
    // VGA output - RGB888 format
    output reg[7:0] vga_out_r,
    output reg[7:0] vga_out_g,
    output reg[7:0] vga_out_b,
    output wire vga_out_vs, vga_out_hs,
    output wire vga_out_sync_n,
    output wire vga_out_blank_n,
    output wire vga_out_clk
);
    wire video_on;
    reg[15:0] pixel_data_reg;
    reg video_on_prev; 
    reg data_valid;    
    reg rd_en_prev;

    // FIFO read enable logic - VGA 클럭 도메인에서 동작
    always @(posedge clk_vga, negedge rst_n) begin
        if (!rst_n) begin
            rd_en <= 0;
            pixel_data_reg <= 0;
            video_on_prev <= 0;
            rd_en_prev <= 0;
        end else begin
            video_on_prev <= video_on;
            rd_en_prev <= rd_en;
            
            // 비디오 활성 영역에서만 데이터 읽기
            if (video_on && pixel_x < 640 && pixel_y < 480) begin
                // 카메라 영상 영역에서만 읽기 요청
                if (pixel_x >= 160 && pixel_x < 480 && pixel_y >= 120 && pixel_y < 360) begin
                    rd_en <= 1;
                    // 이전 사이클에서 읽기 요청했으면 데이터 래치
                    if (rd_en_prev && !empty_fifo) begin
                        pixel_data_reg <= din;
                    end
                end else begin
                    rd_en <= 0;
                end
            end else begin
                rd_en <= 0;
            end
        end
    end
     
    // VGA output logic - VGA 클럭 도메인에서 동작
    always @(posedge clk_vga, negedge rst_n) begin
        if (!rst_n) begin
            vga_out_r <= 8'h00;
            vga_out_g <= 8'h00;
            vga_out_b <= 8'h00;
        end else begin
            if (video_on) begin
                // 320x240 카메라 영상 영역 (중앙 배치)
                if (pixel_x >= 160 && pixel_x < 480 && pixel_y >= 120 && pixel_y < 360) begin
                    // BRAM에서 유효한 데이터가 있으면 표시
                    if (!empty_fifo && pixel_data_reg != 0) begin
                        // RGB565 to RGB888 변환 (정확한 비트 매핑)
                        vga_out_r <= {pixel_data_reg[15:11], pixel_data_reg[15:13]};
                        vga_out_g <= {pixel_data_reg[10:5],  pixel_data_reg[10:9]};
                        vga_out_b <= {pixel_data_reg[4:0],   pixel_data_reg[4:2]};
                    end else begin
                        // 데이터가 없으면 테스트 패턴 (카메라가 동작하는지 확인용)
                        // 체크보드 패턴으로 변경
                        if (((pixel_x[4] ^ pixel_y[4]) == 1)) begin
                            vga_out_r <= 8'hFF;
                            vga_out_g <= 8'h00;
                            vga_out_b <= 8'h00;
                        end else begin
                            vga_out_r <= 8'h00;
                            vga_out_g <= 8'hFF;
                            vga_out_b <= 8'h00;
                        end
                    end
                end else begin
                    // 카메라 영역 밖: 파란색 테두리
                    vga_out_r <= 8'h00;
                    vga_out_g <= 8'h00;
                    vga_out_b <= 8'h80;
                end
            end else begin
                // Blanking period (검은색)
                vga_out_r <= 8'h00;
                vga_out_g <= 8'h00;
                vga_out_b <= 8'h00;
            end
        end
    end
     
    // DE2-115 VGA DAC control signals
    assign vga_out_clk = clk_vga;
    assign vga_out_sync_n = 1'b0; // Use separate HSYNC and VSYNC
    assign vga_out_blank_n = video_on; // Blank when not in active display area
    
    // VGA Core: Generates VGA timing signals (HSYNC, VSYNC, etc.)
    vga_core vga_timing_gen (
        .clk(clk_vga),
        .rst_n(rst_n),  
        .hsync(vga_out_hs),
        .vsync(vga_out_vs),
        .video_on(video_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );
     
endmodule