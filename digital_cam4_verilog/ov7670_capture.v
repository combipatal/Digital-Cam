// VHDL 소스 파일: ov7670_capture.vhd
// 이 모듈은 OV7670 카메라로부터 들어오는 프레임의 픽셀 데이터를 캡처하여 Block RAM에 저장합니다.
// [수정됨] end_of_frame 신호를 안정적인 Handshake 방식으로 변경

module ov7670_capture (
    input wire          pclk,
    input wire          vsync,
    input wire          href,
    input wire  [7:0]   d,
    // --- Handshake 신호를 위한 포트 추가 ---
    input wire          clr_end_of_frame, // FSM으로부터 받는 '확인/클리어' 신호
    
    output wire [16:0]  addr,
    output wire [11:0]  dout,
    output wire         we,
    output wire         end_of_frame
);

    reg [15:0]  d_latch = 16'd0;
    reg [16:0]  address = 17'd0;
    reg [1:0]   line = 2'd0;
    reg [6:0]   href_last = 7'd0;
    reg         we_reg = 1'b0;
    reg         end_of_frame_reg = 1'b0;
    reg         href_hold = 1'b0;
    reg         latched_vsync = 1'b0;
    reg         latched_href = 1'b0;
    reg [7:0]   latched_d = 8'd0;

    assign addr = address;
    assign we = we_reg;
    assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};
    assign end_of_frame = end_of_frame_reg;

    always @(posedge pclk) begin
        if (we_reg) begin
            address <= address + 1;
        end

        if (~href_hold && latched_href) begin
            case (line)
                2'b00: line <= 2'b01;
                2'b01: line <= 2'b10;
                2'b10: line <= 2'b11;
                default: line <= 2'b00;
            endcase
        end
        href_hold <= latched_href;

        if (latched_href) begin
            d_latch <= {d_latch[7:0], latched_d};
        end
        we_reg <= 1'b0;

        // --- 수정된 end_of_frame 로직 ---
        // FSM이 신호를 확인하고 클리어 신호를 보내면 '0'으로 리셋
        if(clr_end_of_frame) begin
            end_of_frame_reg <= 1'b0;
        // 새로운 프레임이 시작되면 (vsync), '1'로 설정하고 유지
        end else if (latched_vsync) begin
            address <= 17'd0;
            href_last <= 7'd0;
            line <= 2'd0;
            end_of_frame_reg <= 1'b1;
        end else begin
            if (href_last[2]) begin
                if (line[1]) begin
                    we_reg <= 1'b1;
                end
                href_last <= 7'd0;
            end else begin
                href_last <= {href_last[5:0], latched_href};
            end
        end
    end

    always @(negedge pclk) begin
        latched_d <= d;
        latched_href <= href;
        latched_vsync <= vsync;
    end

endmodule