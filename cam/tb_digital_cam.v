`timescale 1ns/1ps
module tb_digital_cam;

reg clk_50MHz;
reg clk_25MHz;
reg wren;
reg [16:0] wraddress;
reg [15:0] wrdata;
reg [2:0] active_filter_mode;

wire vga_enable;

reg [15:0] frame_mem [0:320*240-1]; // 320x240 프레임 메모리
wire [7:0] sobel_value;
wire [7:0] canny_value;

wire filter_ready = vga_enable;
wire sobel_ready;
wire canny_ready;

test_digital_cam_top test_digital_cam_top_inst (
    .clk_50MHz(clk_50MHz),
    .clk_25MHz(clk_25MHz),
    .wren(wren),
    .wraddress(wraddress),
    .wrdata(wrdata),
    .active_filter_mode(active_filter_mode), 
    .vga_enable(vga_enable),
    .sobel_value(sobel_value),
    .sobel_ready(sobel_ready),
    .canny_value(canny_value),
    .canny_ready(canny_ready)
);


initial begin   //초기화
    $readmemh("C:/git/Verilog-HDL/cam/out_rgb565.hex", frame_mem);
    clk_50MHz = 0;  
    clk_25MHz = 0;
    wren = 0;
    wraddress = 0;
    wrdata = 0;
    active_filter_mode = 3'd3; // Canny 필터 모드
end

always #10 clk_50MHz = ~clk_50MHz;  // 50MHz 클럭 생성
always #20 clk_25MHz = ~clk_25MHz;  // 25MHz 클럭 생성

reg [16:0] idx = 0;
always @(posedge clk_25MHz) begin // 데이터 쓰기
    if (idx < 320*240) begin
        wraddress <= idx;
        wrdata <= frame_mem[idx];
        wren <= 1;
        idx <= idx + 1;
    end else begin
        wren <= 0;
    end
end

localparam integer IMG_WIDTH  = 640;
localparam integer IMG_HEIGHT = 480;
localparam integer IDX_MAX    = IMG_WIDTH * IMG_HEIGHT; // 전체 VGA 프레임(640x480) dump
integer px_fd; // 필터 결과 파일 디스크립터
integer px_cnt = 0; // 픽셀 값 카운트

initial begin
    px_fd = $fopen( "C:/git/Verilog-HDL/cam/px_value_canny.hex", "w");
    if (px_fd == 0) begin
        $display("Failed to open px_value.hex file");
    end
    px_cnt = 0;
end
// 9clk 지연 필요


always @(posedge clk_25MHz) begin
    if (!filter_ready && canny_ready && px_cnt < IDX_MAX) begin
        $fwrite(px_fd, "%02h\n", canny_value); // 픽셀 값 쓰기
        px_cnt <= px_cnt + 1; // 픽셀 값 카운트 증가
        if (px_cnt == IDX_MAX - 1) begin
            $display("Pixel dump completed");
            $fclose(px_fd);
            $finish;
        end
    end
end
endmodule
