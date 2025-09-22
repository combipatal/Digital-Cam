// OV7670 캡처 모듈
// 카메라로부터 QVGA(320x240) 해상도의 픽셀 데이터를 캡처하여 프레임 버퍼 RAM에 저장합니다.
module ov7670_capture (
    input  wire        pclk,    // 픽셀 클럭 (카메라 제공)
    input  wire        vsync,   // 수직 동기화 신호
    input  wire        href,    // 수평 참조 신호 (라인 데이터 유효)
    input  wire [7:0]  d,       // 픽셀 데이터 (8비트)
    output wire [16:0] addr,    // RAM 쓰기 주소 (320*240 = 76800)
    output wire [15:0] dout,    // RAM 쓰기 데이터 (RGB565 16비트)
    output reg         we       // RAM 쓰기 활성화 신호
);

    // 내부 레지스터
    reg [15:0] d_latch = 16'h0000;    // 16비트 픽셀 데이터 래치 (RGB565)
    reg [16:0] address = 17'h00000;   // RAM 쓰기 주소
    reg [9:0]  h_count = 10'd0;       // 수평 바이트 카운터 (0-639)
    reg [8:0]  v_count = 9'd0;        // 수직 라인 카운터 (0-239)
    reg [8:0]  h_pix   = 9'd0;        // 라인 내 픽셀 카운터 (0-319)

    // 입력 신호 래치 (타이밍 안정성 확보)
    reg latched_vsync = 1'b0;
    reg latched_href = 1'b0;
    reg [7:0] latched_d = 8'h00;

    // HREF 에지 검출용 이전 상태
    reg prev_href = 1'b0;

    // 출력 신호 연결
    assign addr = address;
    assign dout = d_latch;

    // 픽셀 데이터 및 주소 처리 로직
    always @(posedge pclk) begin
        // VSYNC가 활성화되면 새 프레임 시작: 모든 카운터와 주소 리셋
        if (latched_vsync == 1'b1) begin
            address <= 17'h00000;
            h_count <= 10'd0;
            h_pix   <= 9'd0;
            v_count <= 9'd0;
            we <= 1'b0;
        end else begin
            // HREF 에지 검출
            if (!prev_href && latched_href) begin
                // 라인 시작: 픽셀 카운터 정렬
                h_count <= 10'd0;
                h_pix   <= 9'd0;
            end else if (prev_href && !latched_href) begin
                // 라인 종료: 다음 라인으로 이동
                if (v_count < 9'd239) begin
                    v_count <= v_count + 1'b1;
                end else begin
                    v_count <= 9'd0;
                end
            end
            prev_href <= latched_href;

            if (latched_href == 1'b1) begin
                // RGB565는 2바이트(16비트) 데이터
                d_latch <= {d_latch[7:0], latched_d};

                // 기본값: 쓰기 비활성
                we <= 1'b0;

                // 홀수 번째 바이트(두 번째 바이트)에서 픽셀 1개 완료
                if (h_count[0] == 1'b1) begin
                    if (h_pix < 9'd320) begin
                        // 주소 = v*320 + h (320 = 256 + 64)
                        address <= ({8'd0, v_count} << 8) + ({8'd0, v_count} << 6) + {8'd0, h_pix};
                        we <= 1'b1; // 한 사이클 쓰기
                        // 다음 픽셀 인덱스
                        h_pix <= h_pix + 1'b1;
                    end else begin
                        we <= 1'b0;
                    end
                end

                // 바이트 카운터 0..639
                if (h_count < 10'd639) begin
                    h_count <= h_count + 1'b1;
                end else begin
                    h_count <= 10'd0;
                end
            end else begin
                // 비활성 구간
                we <= 1'b0;
                h_count <= 10'd0;
            end
        end
    end

    // 입력 신호 래치: pclk의 하강 에지에서 캡처하여 안정적인 데이터 처리
    always @(negedge pclk) begin
        latched_d <= d;
        latched_href <= href;
        latched_vsync <= vsync;
    end

endmodule
